/**
  * @ClassName yolo_image
  * @Description inference code for yolo
  * @Author raul.rao
  * @Date 2022/5/23 11:10
  * @Version 2.0 (Refactored for Multi-Model Support)
  */

#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <memory>
#include <sstream>
#include <string>
#include <vector>
#include <ctime>

#include <cstdint>

#include "rknn_api.h"
#include "yolo_image.h"
#include "model_holder.h" // [NEW] Include ModelHolder

#include "rga/rga.h"
#include "rga/im2d.h"
#include "rga/im2d_version.h"
#include "post_process.h"

//#define DEBUG_DUMP
//#define EVAL_TIME
#define ZERO_COPY 1
#define DO_NOT_FLIP -1

double __get_us(struct timeval t) { return (t.tv_sec * 1000000 + t.tv_usec); }

// Helper to clean up generic memory
static void cleanup_model(ModelHolder* h) {
    if (!h) return;
    if (h->ctx) {
        // destroy inputs
        for (uint32_t i = 0; i < h->n_input; ++i) {
            if (h->input_mems[i]) {
                rknn_destroy_mem(h->ctx, h->input_mems[i]);
                h->input_mems[i] = nullptr;
            }
        }
        // destroy outputs
        for (uint32_t i = 0; i < h->n_output; ++i) {
            if (h->output_mems[i]) {
                rknn_destroy_mem(h->ctx, h->output_mems[i]);
                h->output_mems[i] = nullptr;
            }
        }
        rknn_destroy(h->ctx);
        h->ctx = 0;
    }
    delete h;
}

// -------------------------------------------------------------
// Callbacks / implementation
// -------------------------------------------------------------

// Returns handle (pointer to ModelHolder) as int64_t, or 0 on failure
int64_t create(int im_height, int im_width, int im_channel, char *model_path)
{
    LOGI("try rknn_init! Model: %s", model_path);

    // 0. RGA version check
    // LOGI("RGA API Version: %s", RGA_API_VERSION)

    ModelHolder* h = new ModelHolder();
    h->img_height = im_height;
    h->img_width = im_width;

    // 1. Load model
    FILE *fp = fopen(model_path, "rb");
    if(fp == NULL) {
        LOGE("fopen %s fail!\n", model_path);
        delete h;
        return 0;
    }
    fseek(fp, 0, SEEK_END);
    uint32_t model_len = ftell(fp);
    void *model = malloc(model_len);
    fseek(fp, 0, SEEK_SET);
    if(model_len != fread(model, 1, model_len, fp)) {
        LOGE("fread %s fail!\n", model_path);
        free(model);
        fclose(fp);
        delete h;
        return 0;
    }

    fclose(fp);

    // 2. Init RKNN model
    // Enable RKNN_FLAG_PRIOR_HIGH (1) to ensure NPU usage
    int ret = rknn_init(&h->ctx, model, model_len, 1, nullptr);
    free(model);

    if(ret < 0) {
        LOGE("rknn_init fail! ret=%d\n", ret);
        delete h;
        return 0;
    }

    // 3. Query input/output attr.
    rknn_input_output_num io_num;
    rknn_query_cmd cmd = RKNN_QUERY_IN_OUT_NUM;
    // 3.1 Query input/output num.
    ret = rknn_query(h->ctx, cmd, &io_num, sizeof(io_num));
    if (ret != RKNN_SUCC) {
        LOGE("rknn_query io_num fail!ret=%d\n", ret);
        cleanup_model(h);
        return 0;
    }
    h->n_input = io_num.n_input;
    h->n_output = io_num.n_output;

    // 3.2 Query input attributes
    if (h->n_input > ModelHolder::MAX_IO_NUM) {
         LOGE("Input count %d exceeds MAX_IO_NUM", h->n_input);
         cleanup_model(h); 
         return 0;
    }
    
    memset(h->input_attrs, 0, sizeof(h->input_attrs));
    for (int i = 0; i < h->n_input; ++i) {
        h->input_attrs[i].index = i;
        cmd = RKNN_QUERY_INPUT_ATTR;
        ret = rknn_query(h->ctx, cmd, &(h->input_attrs[i]), sizeof(rknn_tensor_attr));
        if (ret < 0) {
            LOGE("rknn_query input_attrs[%d] fail!ret=%d\n", i, ret);
            cleanup_model(h);
            return 0;
        }
    }
    
    // 3.2.0 Update global model input shape.
    if (RKNN_TENSOR_NHWC == h->input_attrs[0].fmt) {
        h->m_in_height = h->input_attrs[0].dims[1];
        h->m_in_width = h->input_attrs[0].dims[2];
        h->m_in_channel = h->input_attrs[0].dims[3];
    } else if (RKNN_TENSOR_NCHW == h->input_attrs[0].fmt) {
        h->m_in_height = h->input_attrs[0].dims[2];
        h->m_in_width = h->input_attrs[0].dims[3];
        h->m_in_channel = h->input_attrs[0].dims[1];
    } else {
        LOGE("Unsupported model input layout: %d!\n", h->input_attrs[0].fmt);
        cleanup_model(h);
        return 0;
    }

    // set scale_w, scale_h for post process
    // STRETCH MODE: Direct resize without aspect ratio preservation
    h->scale_w = (float)h->m_in_width / h->img_width;
    h->scale_h = (float)h->m_in_height / h->img_height;

    h->pad_w = 0;
    h->pad_h = 0;

    LOGI("===== RKNN INIT (STRETCH MODE) =====");
    LOGI("Input image: %dx%d", h->img_width, h->img_height);
    LOGI("Model input: %dx%d", h->m_in_width, h->m_in_height);
    LOGI("Scale: w=%.3f h=%.3f (NO PADDING)", h->scale_w, h->scale_h);
    LOGI("====================");


    if (h->n_output > ModelHolder::MAX_IO_NUM) {
         LOGE("Output count %d exceeds MAX_IO_NUM", h->n_output);
         cleanup_model(h);
         return 0;
    }
    
    memset(h->output_attrs, 0, sizeof(h->output_attrs));
    for (int i = 0; i < h->n_output; ++i) {
        h->output_attrs[i].index = i;
        cmd = RKNN_QUERY_OUTPUT_ATTR;
        ret = rknn_query(h->ctx, cmd, &(h->output_attrs[i]), sizeof(rknn_tensor_attr));
        if (ret < 0) {
            LOGE("rknn_query output_attrs[%d] fail!ret=%d\n", i, ret);
            cleanup_model(h);
            return 0;
        }
        
        LOGI("Output %d: fmt=%d (NHWC=%d, NCHW=%d) n_dims=%d type=%d",
             i, h->output_attrs[i].fmt, RKNN_TENSOR_NHWC, RKNN_TENSOR_NCHW,
             h->output_attrs[i].n_dims, h->output_attrs[i].type);
             
        char dims_str[128] = {0};
        int offset = 0;
        for(int j=0; j<h->output_attrs[i].n_dims; j++) {
            offset += sprintf(dims_str + offset, "%d ", h->output_attrs[i].dims[j]);
        }
        LOGI("Output %d dims: [%s]", i, dims_str);

        // set out_scales/out_zps for post_process
        h->out_scales.push_back(h->output_attrs[i].scale);
        h->out_zps.push_back(h->output_attrs[i].zp);
    }

#if ZERO_COPY
    // 4. Set input/output buffer
    // 4.1 Set inputs memory
    // 4.1.1 Create input tensor memory
    h->input_mems[0] = rknn_create_mem(h->ctx, h->input_attrs[0].size_with_stride * sizeof(char));
    memset(h->input_mems[0]->virt_addr, 0, h->input_attrs[0].size_with_stride * sizeof(char));
    
    // 4.1.2 Update input attrs
    h->input_attrs[0].index = 0;
    h->input_attrs[0].type = RKNN_TENSOR_UINT8;
    h->input_attrs[0].size = h->m_in_height * h->m_in_width * h->m_in_channel * sizeof(char);
    h->input_attrs[0].fmt = RKNN_TENSOR_NHWC;
    h->input_attrs[0].pass_through = 0;
    
    // 4.1.3 Set input buffer
    rknn_set_io_mem(h->ctx, h->input_mems[0], &(h->input_attrs[0]));
    
    // 4.1.4 bind virtual address to rga virtual address
    // This destination is the model input buffer
    h->g_rga_dst = wrapbuffer_virtualaddr((void *)h->input_mems[0]->virt_addr, h->m_in_width, h->m_in_height,
                                       RK_FORMAT_RGB_888);

    // 4.2 Set outputs memory
    for (int i = 0; i < h->n_output; ++i) {
        h->output_mems[i] = rknn_create_mem(h->ctx, h->output_attrs[i].n_elems * sizeof(float));
        memset(h->output_mems[i]->virt_addr, 0, h->output_attrs[i].n_elems * sizeof(float));
        h->output_attrs[i].type = RKNN_TENSOR_FLOAT32;
        rknn_set_io_mem(h->ctx, h->output_mems[i], &(h->output_attrs[i]));
    }
#else
    // Legacy path - allocate simple buffer
    void *in_data = malloc(h->m_in_width * h->m_in_height * h->m_in_channel);
    memset(in_data, 0, h->m_in_width * h->m_in_height * h->m_in_channel);
    h->g_rga_dst = wrapbuffer_virtualaddr(in_data, h->m_in_width, h->m_in_height, RK_FORMAT_RGB_888);
#endif

    h->created = true;
    LOGI("rknn_init success!");
    return (int64_t)h;
}

void destroy(int64_t handle) {
    ModelHolder* h = (ModelHolder*)handle;
    if (h) {
        cleanup_model(h);
    }
}

static void transpose_nhwc_to_nchw(float* src, float* dst, int H, int W, int C) {
    for (int h = 0; h < H; h++) {
        for (int w = 0; w < W; w++) {
            for (int c = 0; c < C; c++) {
                // NHWC index: h * W * C + w * C + c
                // NCHW index: c * H * W + h * W + w
                dst[c * H * W + h * W + w] = src[h * W * C + w * C + c];
            }
        }
    }
}

bool run_model(int64_t handle, char *inDataRaw, char *y0, char *y1, char *y2)
{
    ModelHolder* h = (ModelHolder*)handle;
    if(!h || !h->created) {
        LOGE("run_yolo: Invalid handle or not created!");
        return false;
    }

    h->g_rga_src = wrapbuffer_virtualaddr((void *)inDataRaw, h->img_width, h->img_height,
                                       RK_FORMAT_RGBA_8888);

    // convert color format and resize. RGA8888 -> RGB888
    
    // YOLOv5 standard padding color is 114 (grey), not 0 (black)
    // BUT for stretch mode, this doesn't matter since we're resizing to full area
#if ZERO_COPY
     // No need to clear for stretch mode
#else
     // No memset needed for stretch mode
#endif

    // STRETCH MODE: Direct resize without padding

    // Direct stretch resize to full model input size
    im_rect srect = {0, 0, h->img_width, h->img_height};
    im_rect drect = {0, 0, h->m_in_width, h->m_in_height};
    im_rect prect = {0, 0, h->m_in_width, h->m_in_height};

    // Use imresize for simple stretch (no letterboxing)
    int ret = imresize(h->g_rga_src, h->g_rga_dst);
    if (ret != IM_STATUS_SUCCESS) {
        LOGE("run_model: improcess failed: %d %s", ret, imStrError((IM_STATUS)ret));
        return false;
    }

#if ZERO_COPY
    // Inputs are already set via memory binding in create()
#else
    rknn_input inputs[1];
    memset(inputs, 0, sizeof(inputs));
    inputs[0].index = 0;
    inputs[0].type = RKNN_TENSOR_UINT8;
    inputs[0].size = h->m_in_width * h->m_in_height * h->m_in_channel;
    inputs[0].fmt = RKNN_TENSOR_NHWC;
    inputs[0].pass_through = 0;
    inputs[0].buf = h->g_rga_dst.vir_addr;
    rknn_inputs_set(h->ctx, 1, inputs);
#endif

    ret = rknn_run(h->ctx, nullptr);
    if(ret < 0) {
        LOGE("rknn_run fail! ret=%d\n", ret);
        return false;
    }

#if ZERO_COPY
    // Copy output results from device memory (mapped) to user buffers
    // Note: We check format here. If NHWC or UNDEFINED (common in fp16 models), we assume NHWC and transpose to NCHW.
    
    char* output_bufs[3] = {y0, y1, y2};
    for (int i = 0; i < h->n_output; ++i) {
        if (!output_bufs[i]) continue;

        int H = 0, W = 0, C = 0;
        bool is_nhwc = (h->output_attrs[i].fmt == RKNN_TENSOR_NHWC || h->output_attrs[i].fmt == RKNN_TENSOR_UNDEFINED);
        
        if (is_nhwc) {
            // Determine logical H, W, C for transposition
            // Logic: Flatten everything to [C, H, W] vs [H, W, C]
            // From logs: n_dims=5, dims=[1, 3, 85, 40, 40]
            // This is [N, Anchors, Channels, GridH, GridW]
            
            if (h->output_attrs[i].n_dims == 5) {
               // Assuming N, A, C, H, W or N, H, W, A, C
               // For YOLOv5, it's usually N, A, C, H, W (NCHW-like) or N, H, W, A, C (NHWC-like)
               // If RKNN_TENSOR_NHWC is set, it implies the last dim is channel-like.
               // Let's assume the 5D output is [N, H, W, A, C] or [N, A, H, W, C]
               // The transpose_nhwc_to_nchw expects H, W, C.
               // If it's [N, H, W, A, C], then H=dims[1], W=dims[2], C=dims[3]*dims[4]
               // If it's [N, A, H, W, C], then H=dims[2], W=dims[3], C=dims[1]*dims[4]
               // Given the previous code's assumption of dims[1]=H, dims[2]=W, dims[3]=C for 4D NHWC,
               // let's try to map it similarly.
               // For 5D, if it's NHWC, it's likely [N, H, W, C_combined] where C_combined = A*C_per_anchor
               // Or, it could be [N, H, W, A, C_per_anchor] and we need to flatten A, C_per_anchor into C.
               // The most common 5D output for YOLO is [N, num_anchors, grid_h, grid_w, num_classes+5]
               // If RKNN reports it as NHWC, it means the last dimension is the channel.
               // So, dims[0]=N, dims[1]=H, dims[2]=W, dims[3]=A, dims[4]=C_per_anchor
               // We need to transpose to NCHW, which means [N, C_combined, H, W]
               // So, H = dims[1], W = dims[2], C = dims[3] * dims[4]
               H = h->output_attrs[i].dims[1];
               W = h->output_attrs[i].dims[2];
               C = h->output_attrs[i].dims[3] * h->output_attrs[i].dims[4];
            } else if (h->output_attrs[i].n_dims == 4) {
               // Standard 4D NHWC: [N, H, W, C]
               H = h->output_attrs[i].dims[1];
               W = h->output_attrs[i].dims[2];
               C = h->output_attrs[i].dims[3];
            } else {
               // Fallback / Error case, use previous logic
               LOGE("Unexpected n_dims for NHWC output %d: %d. Falling back to dims[1]=H, dims[2]=W, dims[3]=C", i, h->output_attrs[i].n_dims);
               H = h->output_attrs[i].dims[1];
               W = h->output_attrs[i].dims[2];
               C = h->output_attrs[i].dims[3]; 
            }
            
            if (i == 0) { 
                LOGI("Transposing output %d (NHWC->NCHW): H=%d W=%d C=%d (From n_dims=%d)", 
                     i, H, W, C, h->output_attrs[i].n_dims);
            }

            // Perform transpose
            transpose_nhwc_to_nchw(
                (float*)h->output_mems[i]->virt_addr, 
                (float*)output_bufs[i], 
                H, W, C
            );
        } else {
            // NCHW (standard copy)
            memcpy(output_bufs[i], h->output_mems[i]->virt_addr, h->output_attrs[i].n_elems * sizeof(float));
        }
    }

#else
    rknn_output outputs[3];
    memset(outputs, 0, sizeof(outputs));
    for (int i = 0; i < 3; ++i) outputs[i].want_float = 0; 
    
    rknn_outputs_get(h->ctx, 3, outputs, NULL);
    
    // For legacy non-zero-copy path, we just do memcpy for now. 
    // Assuming low-priority or likely NCHW if using old path.
    if (y0) memcpy(y0, outputs[0].buf, h->output_attrs[0].n_elems * sizeof(float));
    if (y1) memcpy(y1, outputs[1].buf, h->output_attrs[1].n_elems * sizeof(float));
    if (y2) memcpy(y2, outputs[2].buf, h->output_attrs[2].n_elems * sizeof(float));
    rknn_outputs_release(h->ctx, 3, outputs);
#endif

    return true;
}

// Helper to draw a hollow rectangle on RGBA buffer
void draw_box_rgba(uint8_t* pixels, int img_w, int img_h, int x1, int y1, int x2, int y2) {
    // Clamp coordinates
    x1 = std::max(0, std::min(x1, img_w - 1));
    y1 = std::max(0, std::min(y1, img_h - 1));
    x2 = std::max(0, std::min(x2, img_w - 1));
    y2 = std::max(0, std::min(y2, img_h - 1));
    
    int thickness = 4;
    uint32_t color = 0xFF0000FF; // Red in ABGR (or RGBA depending on endianness). Let's maximize distinctiveness of 0xFF0000FF
    // If Little Endian: R=FF, G=00, B=00, A=FF.
    
    // Horizontal lines
    for (int y = y1; y < y1 + thickness && y < img_h; y++) {
        for (int x = x1; x <= x2; x++) {
            ((uint32_t*)pixels)[y * img_w + x] = color;
        }
    }
    for (int y = y2 - thickness; y <= y2 && y >= 0; y++) {
        for (int x = x1; x <= x2; x++) {
            ((uint32_t*)pixels)[y * img_w + x] = color;
        }
    }
    // Vertical lines
    for (int x = x1; x < x1 + thickness && x < img_w; x++) {
        for (int y = y1; y <= y2; y++) {
            ((uint32_t*)pixels)[y * img_w + x] = color;
        }
    }
    for (int x = x2 - thickness; x <= x2 && x >= 0; x++) {
        for (int y = y1; y <= y2; y++) {
            ((uint32_t*)pixels)[y * img_w + x] = color;
        }
    }
}

int post_process(int64_t handle, char *grid0_buf, char *grid1_buf, char *grid2_buf,
                      int *ids, float *scores, float *boxes) {
    ModelHolder* h = (ModelHolder*)handle;
    if(!h || !h->created) {
        LOGE("yolo_post_process: Invalid handle!");
        return -1;
    }

    detect_result_group_t detect_result_group;
    
    // Call the overloaded post_process logic (assumed to be linked in post_process.cc)
    // Note: We need to make sure post_process.cc/h is compatible or if we need to pass params differently.
    // The previous code called `post_process(...)`.
    // Let's assume `post_process.h` exposes the calculation function.
    
    int ret = post_process((float *)grid0_buf, (float *)grid1_buf, (float *)grid2_buf,
                       h->m_in_height, h->m_in_width, BOX_THRESH, NMS_THRESH, h->scale_w, h->scale_h,
                       h->pad_w, h->pad_h,
                       h->out_zps, h->out_scales, &detect_result_group);

    if (ret < 0) {
        LOGE("yolo_post_process: post process failed!");
        return -1;
    }

    // Fill return values
    int count = detect_result_group.count;
    for(int i=0; i<count; ++i) {
        ids[i] = detect_result_group.results[i].class_id;
        scores[i] = detect_result_group.results[i].prop;
        
        boxes[i*4 + 0] = detect_result_group.results[i].box.left;
        boxes[i*4 + 1] = detect_result_group.results[i].box.top;
        boxes[i*4 + 2] = detect_result_group.results[i].box.right;
        boxes[i*4 + 3] = detect_result_group.results[i].box.bottom;
        
        // DRAW ON BITMAP
        if (h->g_rga_src.vir_addr) {
             draw_box_rgba((uint8_t*)h->g_rga_src.vir_addr, h->img_width, h->img_height,
                           (int)boxes[i*4+0], (int)boxes[i*4+1], (int)boxes[i*4+2], (int)boxes[i*4+3]);
        }
    }

    return count;
}


// ==========================================
// Dart FFI Bridge
// ==========================================

extern "C" __attribute__((visibility("default"))) __attribute__((used))
int64_t rknn_init_dart(const char* model_path, int32_t width, int32_t height, int32_t channels) {
    // Returns handle (int64_t address of ModelHolder)
    return create(height, width, channels, (char*)model_path); 
}

extern "C" __attribute__((visibility("default"))) __attribute__((used))
int32_t rknn_run_dart(int64_t handle, uint8_t* in_data, int32_t* out_ids, float* out_scores, float* out_boxes) {
    ModelHolder* h = (ModelHolder*)handle;
    if(!h || !h->created) return -1;
    
    // 1. Run Inference (Includes RGA resize inside run_model)
    // Note: run_model expects pointers to where to output y0, y1, y2.
    // But here we are calling post_process immediately after?
    // Run_model in the ORIGINAL code copied data to y0, y1, y2 buffers provided by arguments.
    // Then post_process was called with those buffers.
    // We need those intermediate buffers!
    // We cannot just pass null. The post_process function takes them as input.
    
    // Allocate intermediate buffers for the 3 output grids
    // We can use the memory already in ModelHolder if ZERO_COPY, but run_model does the memcpy.
    // Optimization: If ZERO_COPY, `run_model` can just return true and we use the pointers directly from `h` in `post_process`?
    // BUT `post_process` signature expects `char*` buffers.
    
    // Let's stick to the previous flow to minimize risk, but we need to allocate `y0, y1, y2`.
    // Wait, the previous `rknn_run_dart` implementation:
    /*
    int32_t rknn_run_dart(...) {
        // ... wrap/resize ...
        rknn_run();
        // ... post_process(output_mems[0]->virt_addr...)
    }
    */
    // The previous `rknn_run_dart` did NOT call `run_model`. It implemented the logic inline!
    // And it used `output_mems[0]->virt_addr` directly for `post_process`.
    
    // So for this FFI Refactor, I should do the same: Use the handle to access members directly 
    // OR create a helper that does it all.
    
    // Let's implement the logic inline here using the handle, similar to how it was, 
    // OR allow `run_model` to be skipped if we want to access fields directly.
    
    // 1. Resize
    h->g_rga_src = wrapbuffer_virtualaddr((void *)in_data, h->img_width, h->img_height, RK_FORMAT_RGBA_8888);
    int ret = imresize(h->g_rga_src, h->g_rga_dst);
    if (ret != IM_STATUS_SUCCESS) {
        LOGE("rknn_run_dart: resize failed: %d", ret);
        return -1;
    }

    // 2. Run
    ret = rknn_run(h->ctx, nullptr);
    if(ret < 0) {
        LOGE("rknn_run fail! ret=%d", ret);
        return -2;
    }

    // 3. Post Process
    // Use the memory directly from the context (Zero Copy)
    int count = post_process(
        handle,
        (char*)h->output_mems[0]->virt_addr,
        (char*)h->output_mems[1]->virt_addr,
        (char*)h->output_mems[2]->virt_addr,
        (int*)out_ids,
        out_scores,
        out_boxes
    );
    
    return count;
}

extern "C" __attribute__((visibility("default"))) __attribute__((used))
void rknn_destroy_dart(int64_t handle) {
    destroy(handle);
}
