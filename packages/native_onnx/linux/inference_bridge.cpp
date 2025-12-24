#include "inference_bridge.h"
#include <onnxruntime_cxx_api.h>
#include <opencv2/opencv.hpp>
#include <iostream>
#include <vector>
#include <map>
#include <memory>
#include <mutex>
#include <algorithm>

// Global Environment
static std::unique_ptr<Ort::Env> g_env;
static std::unique_ptr<Ort::AllocatorWithDefaultOptions> g_allocator;

// Session Context to hold state per model
struct SessionContext {
    std::unique_ptr<Ort::Session> session;
    std::mutex mutex;  // Per-session mutex for thread safety
    
    // Storage for input names to ensure they stay valid until Run
    std::vector<std::string> input_name_strings;
    
    // Inputs prepared for the next Run
    std::vector<Ort::Value> input_tensors;
    
    // Outputs from the last Run
    std::vector<Ort::Value> output_tensors;
    std::vector<std::vector<int64_t>> current_output_dims;
};

static std::map<int64_t, std::shared_ptr<SessionContext>> g_contexts;
static int64_t g_next_session_id = 1;

// Video Capture State
struct VideoContext {
    std::unique_ptr<cv::VideoCapture> cap;
    std::mutex mutex;  // Per-video mutex for thread safety
    cv::Mat last_frame;
    std::vector<uint8_t> rgb_buffer;
};
static std::map<int64_t, std::shared_ptr<VideoContext>> g_video_contexts;
static int64_t g_next_video_id = 1;

static std::mutex g_contexts_mutex;  // Only for map operations
static std::mutex g_video_mutex;     // Only for map operations

static std::mutex g_env_mutex;

int InitONNX() {
    std::lock_guard<std::mutex> lock(g_env_mutex);
    try {
        if (!g_env) {
            g_env = std::make_unique<Ort::Env>(ORT_LOGGING_LEVEL_WARNING, "NativeInferenceGeneric");
            g_allocator = std::make_unique<Ort::AllocatorWithDefaultOptions>();
        }
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "[Native] Error initializing ONNX: " << e.what() << std::endl;
        return 1;
    }
}

int64_t CreateSession(const char* model_path) {
    std::lock_guard<std::mutex> lock(g_contexts_mutex);
    if (!g_env) InitONNX();

    try {
        Ort::SessionOptions session_options;
        session_options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);

        // GPU Logic
        bool gpu_success = false;
        std::string provider_name = "";

        // 1. Try TensorRT first for best performance
        // try {
        //     std::cout << "[Native] Attempting TensorRT..." << std::endl;
        //     OrtTensorRTProviderOptions trt_options{};
        //     trt_options.device_id = 0;
        //     trt_options.trt_fp16_enable = 1;  // Enable FP16 for 2x speedup
        //     trt_options.trt_max_workspace_size = 2ULL << 30; // 2GB workspace
        //     trt_options.trt_engine_cache_enable = 1; // Cache engines for faster startup
        //     trt_options.trt_engine_cache_enable = 1; // Cache engines for faster startup
        //     trt_options.trt_engine_cache_path = "/tmp/trt_cache"; // Cache directory
        //     // Fix warnings
        //     trt_options.trt_max_partition_iterations = 1000;
        //     trt_options.trt_min_subgraph_size = 1;

        //     session_options.AppendExecutionProvider_TensorRT(trt_options);
        //     gpu_success = true;
        //     provider_name = "TensorRT + CUDA";
        //     // std::cout << "[Native] TensorRT enabled successfully" << std::endl;
        // } catch (const std::exception& e) {
        //      std::cerr << "[Native] TensorRT Init Failed: " << e.what() << std::endl;
        //      gpu_success = false;
        // } catch (...) {
        //      std::cerr << "[Native] TensorRT Init Failed: Unknown Error" << std::endl;
        //      gpu_success = false;
        // }

        // 2. Fallback to CUDA if TensorRT failed
        if (!gpu_success) {
            try {
                std::cout << "[Native] Attempting CUDA..." << std::endl;
                OrtCUDAProviderOptions cuda_options{};
                cuda_options.device_id = 0;
                cuda_options.arena_extend_strategy = 0; // kNextPowerOfTwo for better memory allocation
                cuda_options.gpu_mem_limit = SIZE_MAX; // No limit
                cuda_options.cudnn_conv_algo_search = OrtCudnnConvAlgoSearchExhaustive; // Find best algorithm
                cuda_options.do_copy_in_default_stream = 1;
                
                session_options.AppendExecutionProvider_CUDA(cuda_options);
                gpu_success = true;
                provider_name = "CUDA";
                // std::cout << "[Native] CUDA enabled successfully" << std::endl;
            } catch (const std::exception& e) {
                std::cerr << "[Native] CUDA Init Failed: " << e.what() << std::endl;
            } catch (...) {
                std::cerr << "[Native] CUDA Init Failed: Unknown Error" << std::endl;
            }
        }
        
        if (!gpu_success) {
             std::cerr << "[Native] CRITICAL: Could not enable GPU (TensorRT/CUDA). Aborting session creation." << std::endl;
             // Do NOT fallback to CPU as requested
             return 0;
        } else {
             std::cout << "[Native] Enabled " << provider_name << " for " << model_path << std::endl;
        }

        auto ctx = std::make_shared<SessionContext>();
        ctx->session = std::make_unique<Ort::Session>(*g_env, model_path, session_options);

        int64_t id = g_next_session_id++;
        g_contexts[id] = ctx;
        return id;

    } catch (const std::exception& e) {
        std::cerr << "[Native] CreateSession failed: " << e.what() << std::endl;
        return 0;
    }
}

// ... (Existing release functions) ...

// ==========================================
// Preprocessing
// ==========================================

// Preprocess a raw image buffer (RGB) into a float buffer (NCHW, 1x3x640x640)
// out_data must be pre-allocated (size = 3*640*640 * sizeof(float))
extern "C" __attribute__((visibility("default"))) __attribute__((used))
int PreprocessImage(uint8_t* in_data, int width, int height, float* out_data) {
     try {
        // Wrap input data
        cv::Mat input_img(height, width, CV_8UC3, in_data); // Expecting RGB

        // Blob From Image: Resize to 640x640, Normalize (1/255), SwapRB=false (already RGB?), Crop=false
        // Note: Dart side usually sends RGBA or RGB. If RGBA, we need CV_8UC4 and convert?
        // Let's assume input is 3 channel (RGB) for now based on previous code copying only 3 planes? 
        // Actually earlier code assumed 4 channels in Dart: "imageBytes.buffer, numChannels: 4"
        // But `Video_GetFrame` returns RGBA?
        // Let's check `Video_GetFrame`: "cv::cvtColor(ctx->last_frame, rgb_frame, cv::COLOR_BGR2RGBA);"
        // So input is RGBA.
        
        cv::Mat input_rgba(height, width, CV_8UC4, in_data);
        cv::Mat input_rgb;
        cv::cvtColor(input_rgba, input_rgb, cv::COLOR_RGBA2RGB);

        // blobFromImage handles resizing, scaling (1/255), and NCHW layout
        // input, output, scalefactor, size, mean, swapRB, crop, ddepth
        cv::Mat blob;
        cv::dnn::blobFromImage(input_rgb, blob, 1.0/255.0, cv::Size(640, 640), cv::Scalar(), false, false, CV_32F);
        
        // blob is [1, 3, 640, 640]
        // Copy to output
        size_t size = blob.total() * blob.elemSize();
        std::memcpy(out_data, blob.data, size);
        
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "[Native] PreprocessImage failed: " << e.what() << std::endl;
        return 1;
    }
}

void ReleaseSession(int64_t session_id) {
    std::lock_guard<std::mutex> lock(g_contexts_mutex);
    g_contexts.erase(session_id);
    std::cout << "[Native] Session " << session_id << " released." << std::endl;
}

void Session_ClearInputs(int64_t session_id) {
    std::shared_ptr<SessionContext> ctx;
    {
        std::lock_guard<std::mutex> lock(g_contexts_mutex);
        auto it = g_contexts.find(session_id);
        if (it == g_contexts.end()) return;
        ctx = it->second;
    }
    
    std::lock_guard<std::mutex> lock(ctx->mutex);
    ctx->input_name_strings.clear();
    ctx->input_tensors.clear();
}

void Session_AddInput(int64_t session_id, const char* name, float* data, int64_t* dims, int rank) {
    std::shared_ptr<SessionContext> ctx;
    {
        std::lock_guard<std::mutex> lock(g_contexts_mutex);
        auto it = g_contexts.find(session_id);
        if (it == g_contexts.end()) return;
        ctx = it->second;
    }

    std::lock_guard<std::mutex> lock(ctx->mutex);
    try {
        Ort::MemoryInfo memory_info = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
        
        // Count elements
        size_t size = 1;
        for(int i=0; i<rank; i++) size *= dims[i];
        
        // Wrap data
        Ort::Value tensor = Ort::Value::CreateTensor<float>(
            memory_info, data, size, dims, rank);
            
        // Valid deep copy of string
        ctx->input_name_strings.push_back(std::string(name));
        ctx->input_tensors.push_back(std::move(tensor));
        
    } catch (const std::exception& e) {
        std::cerr << "[Native] AddInput failed: " << e.what() << std::endl;
    }
}

int Session_Run(int64_t session_id, const char** output_names, int num_outputs) {
    std::shared_ptr<SessionContext> ctx;
    {
        std::lock_guard<std::mutex> lock(g_contexts_mutex);
        auto it = g_contexts.find(session_id);
        if (it == g_contexts.end()) return 1;
        ctx = it->second;
    }

    // Lock only THIS session during inference (allows concurrent batches!)
    std::lock_guard<std::mutex> lock(ctx->mutex);
    try {
        // Rebuild const char* array from valid strings
        std::vector<const char*> input_names_ptrs;
        input_names_ptrs.reserve(ctx->input_name_strings.size());
        for (const auto& s : ctx->input_name_strings) {
            input_names_ptrs.push_back(s.c_str());
        }

        ctx->output_tensors = ctx->session->Run(
            Ort::RunOptions{nullptr}, 
            input_names_ptrs.data(), 
            ctx->input_tensors.data(), 
            ctx->input_tensors.size(), 
            output_names,
            num_outputs
        );
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "[Native] Run failed: " << e.what() << std::endl;
        return 2;
    }
}

int Session_GetOutput(int64_t session_id, int index, float** out_data, int64_t** out_dims, int* out_rank, int64_t* out_count) {
    std::shared_ptr<SessionContext> ctx;
    {
        std::lock_guard<std::mutex> lock(g_contexts_mutex);
        auto it = g_contexts.find(session_id);
        if (it == g_contexts.end()) return 1;
        ctx = it->second;
    }
    
    std::lock_guard<std::mutex> lock(ctx->mutex);
    
    if (index < 0 || index >= ctx->output_tensors.size()) return 2;
    
    try {
        auto& tensor = ctx->output_tensors[index];
        
        // Get float data
        *out_data = tensor.GetTensorMutableData<float>();
        
        // Get shape info
        auto type_info = tensor.GetTensorTypeAndShapeInfo();
        
        // We need to return dims array. type_info.GetShape() returns std::vector.
        // We need a stable pointer. We can store it in ctx.
        if (ctx->current_output_dims.size() <= index) {
            ctx->current_output_dims.resize(index + 1);
        }
        ctx->current_output_dims[index] = type_info.GetShape();
        
        *out_dims = ctx->current_output_dims[index].data();
        *out_rank = (int)ctx->current_output_dims[index].size();
        *out_count = type_info.GetElementCount();
        
        return 0;
    } catch (const std::exception& e) {
         std::cerr << "[Native] GetOutput failed: " << e.what() << std::endl;
         return 3;
    }
}

// ==========================================
// Video Capture Implementation
// ==========================================

int64_t Video_Open(const char* url) {
    std::cout << "[Native] Video_Open called for: " << url << std::endl;
    std::lock_guard<std::mutex> lock(g_video_mutex);
    try {
        std::cout << "[Native] Video_Open: Lock acquired. Creating capture..." << std::endl;
        // Use standard OpenCV VideoCapture (auto-detects best backend)
        auto cap = std::make_unique<cv::VideoCapture>(url, cv::CAP_ANY);
        
        if (!cap->isOpened()) {
             std::cerr << "[Native] Failed to open video: " << url << std::endl;
             return 0;
        }
        
        // Verify we can grab at least one frame
        if (!cap->grab()) {
            std::cerr << "[Native] Failed to grab initial frame: " << url << std::endl;
            return 0;
        }
        
        // Optimize for realtime - minimize buffering
        cap->set(cv::CAP_PROP_BUFFERSIZE, 1);
        
        auto ctx = std::make_shared<VideoContext>();
        ctx->cap = std::move(cap);
        
        int64_t id = g_next_video_id++;
        g_video_contexts[id] = ctx;
        
        // std::cout << "[Native] Video opened successfully (ID: " << id << ")" << std::endl;
        return id;
    } catch (const std::exception& e) {
        std::cerr << "[Native] Video_Open error: " << e.what() << std::endl;
        return 0;
    }
}

void Video_Release(int64_t video_id) {
    std::lock_guard<std::mutex> lock(g_video_mutex);
    g_video_contexts.erase(video_id);
    std::cout << "[Native] Video released: " << video_id << std::endl;
}

int Video_GetFrame(int64_t video_id, uint8_t** out_buffer, int* width, int* height) {
    // std::cout << "[Native] GetFrame " << video_id << std::endl; 
    std::shared_ptr<VideoContext> ctx;
    {
        std::lock_guard<std::mutex> lock(g_video_mutex);
        auto it = g_video_contexts.find(video_id);
        if (it == g_video_contexts.end()) {
             std::cerr << "[Native] GetFrame: Invalid ID " << video_id << std::endl;
             return 1; 
        }
        ctx = it->second;
    }
    
    // Lock only THIS video during frame capture
    std::lock_guard<std::mutex> lock(ctx->mutex);
    
    // Use read() instead of grab() + retrieve() for simpler EOF handling
    bool success = ctx->cap->read(ctx->last_frame);
    
    // Handle EOF or Read Failure
    if (!success || ctx->last_frame.empty()) {
        // Attempt to rewind (Looping)
        // Check if it's a file by checking frame count (approximate) or just try seeking
        // For streams, this seek might fail or do nothing, which is fine.
        
        // Only log if it's not a generic failure
        // std::cout << "[Native] Video ID " << video_id << ": Read failed (EOF?). Attempting to rewind..." << std::endl;
        
        ctx->cap->set(cv::CAP_PROP_POS_FRAMES, 0);
        
        // Retry read after rewind
        success = ctx->cap->read(ctx->last_frame);
        
        if (!success || ctx->last_frame.empty()) {
             std::cerr << "[Native] Video ID " << video_id << ": Check failed after rewind. Stopping." << std::endl;
             return 2; // Genuine failure
        }
        
        // std::cout << "[Native] Video ID " << video_id << ": Rewind successful. Looping." << std::endl;
    }

    // Convert BGR (OpenCV default) to RGB or RGBA?
    // Flutter Image.memory expects RGBA or RGB depending on how we decode.
    // Let's use RGB for simplicity.
    cv::Mat rgb_frame;
    cv::cvtColor(ctx->last_frame, rgb_frame, cv::COLOR_BGR2RGBA); // Use RGBA for compatibility with Bitmap/Image
    
    // Copy to persistent buffer
    size_t dataSize = rgb_frame.total() * rgb_frame.elemSize();
    if (ctx->rgb_buffer.size() != dataSize) {
        ctx->rgb_buffer.resize(dataSize);
    }
    std::memcpy(ctx->rgb_buffer.data(), rgb_frame.data, dataSize);
    
    *width = rgb_frame.cols;
    *height = rgb_frame.rows;
    *out_buffer = ctx->rgb_buffer.data();
    
    return 0; // Success
}
