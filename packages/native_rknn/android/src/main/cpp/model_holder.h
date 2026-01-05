#ifndef MODEL_HOLDER_H
#define MODEL_HOLDER_H

#include <vector>
#include <string>
#include "rknn_api.h"
#include "rga/rga.h"
#include "rga/im2d.h"

struct ModelHolder {
    // RKNN Context
    rknn_context ctx = 0;
    bool created = false;

    // Model Info
    int m_in_width = 0;
    int m_in_height = 0;
    int m_in_channel = 0;
    
    // Original Image Info (for resizing)
    int img_width = 0;
    int img_height = 0;

    // Post-process params
    float scale_w = 0.0f;
    float scale_h = 0.0f;
    int pad_w = 0;
    int pad_h = 0;

    // I/O counts
    uint32_t n_input = 0;
    uint32_t n_output = 0;

    // Tensor attributes & memory
    // Assuming max usage based on previous statics (1 input, 3 output for YOLO)
    // Using vectors or fixed arrays. The original code used static arrays [1] and [3].
    // Let's use containers to be safe or fixed size if we want to match strictly.
    // The previous code had `static rknn_tensor_attr input_attrs[1];`
    // Let's stick to safe defaults but allow flexibility.
    static const int MAX_IO_NUM = 8;
    
    rknn_tensor_attr input_attrs[MAX_IO_NUM];
    rknn_tensor_attr output_attrs[MAX_IO_NUM];

    rknn_tensor_mem* input_mems[MAX_IO_NUM] = {nullptr};
    rknn_tensor_mem* output_mems[MAX_IO_NUM] = {nullptr};

    std::vector<float> out_scales;
    std::vector<int32_t> out_zps;

    // RGA Buffers
    rga_buffer_t g_rga_src;
    rga_buffer_t g_rga_dst;
};

#endif // MODEL_HOLDER_H
