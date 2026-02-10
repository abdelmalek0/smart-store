#include "inference_bridge.h"
#include <onnxruntime_cxx_api.h>
#include <opencv2/opencv.hpp>
#include <iostream>
#include <vector>
#include <map>
#include <memory>
#include <mutex>
#include <algorithm>
#include <cstdlib>  // for atexit
#include <atomic>   // for shutdown flag
#include "texture_manager.h"

// Shutdown state
static std::atomic<bool> g_shutdown_called{false};

// Signal handler for graceful shutdown
#include <csignal>

__attribute__((used))
static void signal_handler(int signum) {
    if (!g_shutdown_called.load()) {
        std::cerr << "\n[Native] Signal " << signum << " received - cleaning up..." << std::endl;
        // Can't call Inference_Shutdown directly from signal handler safely
        // Just mark shutdown requested and exit quickly
        g_shutdown_called.store(true);
    }
    // Re-raise signal with default handler to exit
    signal(signum, SIG_DFL);
    raise(signum);
}

// CUDA headers for GPU verification
#ifdef USE_CUDA
#include <cuda_runtime.h>
#endif

// OpenCV CUDA headers for GPU preprocessing
#ifdef HAVE_OPENCV_CUDAIMGPROC
#include <opencv2/cudaimgproc.hpp>
#include <opencv2/cudawarping.hpp>
#endif

// FFmpeg headers for hardware video decoding with NVDEC
#ifdef USE_FFMPEG_NVDEC
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/hwcontext.h>
#include <libavutil/hwcontext_cuda.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
}
#endif

// NPP headers for GPU-native NV12 to RGBA conversion
#ifdef USE_NPP
#include <nppi_color_conversion.h>
#include <npp.h>
#endif

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

    // CPU preprocessing buffer (fallback)
    std::vector<float> preprocess_buffer;
    
    // GPU preprocessing buffer for full GPU inference
    cv::cuda::GpuMat gpu_preprocess_buffer;  // Stores 1x3x640x640 in CHW format
    float* cuda_tensor_ptr = nullptr;        // CUDA memory for ONNX tensor
    size_t cuda_tensor_size = 0;
};

static std::map<int64_t, std::shared_ptr<SessionContext>> g_contexts;
static int64_t g_next_session_id = 1;

#include <chrono>

// Video Capture State with FFmpeg NVDEC
struct VideoContext {
    // Synchronization State
    std::chrono::time_point<std::chrono::steady_clock> start_time;
    bool first_frame_read = false;
    int64_t start_pts = 0;

#ifdef USE_FFMPEG_NVDEC
    // FFmpeg structures for hardware decoding
    AVFormatContext* format_ctx = nullptr;
    AVCodecContext* codec_ctx = nullptr;
    AVBufferRef* hw_device_ctx = nullptr;
    AVFrame* frame = nullptr;
    AVFrame* sw_frame = nullptr;  // For transferring from GPU to CPU
    AVPacket* packet = nullptr;
    struct SwsContext* sws_ctx = nullptr;
    
    int video_stream_idx = -1;
    
    // Output buffer
    std::vector<uint8_t> rgba_buffer;
    int width = 0;
    int height = 0;
    
    // Cache to prevent swscale thrashing
    int last_width = 0;
    int last_height = 0;
    int last_format = -1;
    
    std::mutex mutex;  // Per-video mutex for thread safety
    
    // GPU Texture rendering (NEW)
    int texture_id;  // TextureManager ID
    int texture_manager_id;  // ID from Dart (for updates)
    bool use_gpu_texture;
    
    // GPU frame for zero-copy inference pipeline
    cv::cuda::GpuMat last_rgba_gpu;  // Store last RGBA frame on GPU
    bool has_gpu_frame = false;       // Flag indicating GPU frame is available
    
    // Per-stream NV12 conversion buffer (thread-safe alternative to static)
    std::vector<uint8_t> nv12_buffer;
#else
    // Fallback to OpenCV if FFmpeg not available
    std::unique_ptr<cv::VideoCapture> cap;
    std::mutex mutex;
    cv::Mat last_frame;
    std::vector<uint8_t> rgb_buffer;
#endif
};
static std::map<int64_t, std::shared_ptr<VideoContext>> g_video_contexts;
static int64_t g_next_video_id = 1;

static std::mutex g_contexts_mutex;  // Only for map operations
static std::mutex g_video_mutex;     // Only for map operations

static std::mutex g_env_mutex;



int InitONNX() {
    std::lock_guard<std::mutex> lock(g_env_mutex);
    // Reset shutdown flag to allow restart
    g_shutdown_called.store(false);
    
    try {
        if (!g_env) {
            // Enable WARNING logging to suppress GraphTransformer info logs
            g_env = std::make_unique<Ort::Env>(ORT_LOGGING_LEVEL_WARNING, "NativeONNX");
            g_allocator = std::make_unique<Ort::AllocatorWithDefaultOptions>();
            
            // NOTE: atexit handlers don't work well with Flutter/GTK
            // Cleanup should be called explicitly via NativeInferenceService.shutdown()
            
            std::cout << "[Native] ONNX Runtime initialized" << std::endl;
            
            // ========================================
            // GPU Capability Check
            // ========================================
            std::cout << "[GPU-CHECK] Verifying GPU capabilities..." << std::endl;
            
            // Check CUDA availability
            #ifdef USE_CUDA
            int deviceCount = 0;
            cudaError_t err = cudaGetDeviceCount(&deviceCount);
            if (err == cudaSuccess && deviceCount > 0) {
                cudaDeviceProp prop;
                cudaGetDeviceProperties(&prop, 0);
                std::cout << "[GPU-CHECK] ✓ CUDA Device: " << prop.name 
                         << " (Compute " << prop.major << "." << prop.minor << ")" << std::endl;
                
                // Check cuDNN
                #ifdef CUDNN_MAJOR
                std::cout << "[GPU-CHECK] ✓ cuDNN version: " << CUDNN_MAJOR << "." << CUDNN_MINOR << std::endl;
                #endif
            } else {
                std::cout << "[GPU-CHECK] ⚠ CUDA not available or no devices found" << std::endl;
            }
            #else
            std::cout << "[GPU-CHECK] ⚠ ONNX Runtime not compiled with CUDA support" << std::endl;
            #endif
            
            // Check OpenCV CUDA modules
            #ifdef HAVE_OPENCV_CUDAIMGPROC
            std::cout << "[GPU-CHECK] ✓ OpenCV CUDA modules: ENABLED" << std::endl;
            #else
            std::cout << "[GPU-CHECK] ⚠ OpenCV CUDA modules: NOT AVAILABLE (image resize will use CPU)" << std::endl;
            #endif
            
            std::cout << "[GPU-CHECK] ========================================" << std::endl;
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
        session_options.SetLogSeverityLevel(3); // 3 = ORT_LOGGING_LEVEL_ERROR

        // GPU Logic  
        bool gpu_success = false;
        std::string provider_name = "";
        
        std::cout << "[Native] ========================================" << std::endl;
        std::cout << "[Native] Creating session for: " << model_path << std::endl;

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
                std::cout << "[Native] ✓ CUDA provider added successfully" << std::endl;
            } catch (const std::exception& e) {
                std::cerr << "[Native] ❌ CUDA Init Failed: " << e.what() << std::endl;
                gpu_success = false;
            } catch (...) {
                std::cerr << "[Native] ❌ CUDA Init Failed: Unknown Error" << std::endl;
                gpu_success = false;
            }
        }
        
        if (!gpu_success) {
             std::cerr << "[Native] ❌ CRITICAL: Could not enable GPU (TensorRT/CUDA). Aborting session creation." << std::endl;
             std::cerr << "[Native] Make sure CUDA libraries are in LD_LIBRARY_PATH" << std::endl;
             // Do NOT fallback to CPU as requested
             return 0;
        } else {
             std::cout << "[Native] ✓ Enabled " << provider_name << " for " << model_path << std::endl;
        }
        
        // Log which execution providers will be used
        std::cout << "[Native] Session Options configured, creating session..." << std::endl;

        auto ctx = std::make_shared<SessionContext>();
        ctx->session = std::make_unique<Ort::Session>(*g_env, model_path, session_options);
        
        std::cout << "[Native] ✓ Session created successfully" << std::endl;
        std::cout << "[Native] ========================================" << std::endl;

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

// Preprocess a raw image buffer (RGBA) into a float buffer (NCHW, 1x3x640x640)
// out_data must be pre-allocated (size = 3*640*640 * sizeof(float))
extern "C" __attribute__((visibility("default"))) __attribute__((used))
int PreprocessImage(uint8_t* in_data, int width, int height, float* out_data) {
    try {
        #ifdef HAVE_OPENCV_CUDAIMGPROC
        // ========================================
        // GPU-accelerated preprocessing path
        // ========================================
        static bool first_call = true;
        static int frame_count = 0;
        
        if (first_call) {
            std::cout << "[GPU-PREPROCESS] ========================================" << std::endl;
            std::cout << "[GPU-PREPROCESS] ✓ Using CUDA for image preprocessing" << std::endl;
            std::cout << "[GPU-PREPROCESS] - RGBA->RGB conversion: GPU" << std::endl;
            std::cout << "[GPU-PREPROCESS] - Resize to 640x640: GPU" << std::endl;
            std::cout << "[GPU-PREPROCESS] - Normalize (0-255 -> 0-1): GPU" << std::endl;
            std::cout << "[GPU-PREPROCESS] ========================================" << std::endl;
            first_call = false;
        }
        
        frame_count++;
        if (frame_count % 100 == 0) {
            std::cout << "[GPU-PREPROCESS] Processed " << frame_count << " frames on GPU" << std::endl;
        }
        
        // 1. Create CPU Mat from input data (RGBA)
        cv::Mat input_rgba(height, width, CV_8UC4, in_data);
        
        // 2. Upload to GPU
        cv::cuda::GpuMat gpu_rgba;
        gpu_rgba.upload(input_rgba);
        
        // 3. Convert RGBA -> RGB on GPU
        cv::cuda::GpuMat gpu_rgb;
        cv::cuda::cvtColor(gpu_rgba, gpu_rgb, cv::COLOR_RGBA2RGB);
        
        // 4. Resize to 640x640 on GPU
        cv::cuda::GpuMat gpu_resized;
        cv::cuda::resize(gpu_rgb, gpu_resized, cv::Size(640, 640), 0, 0, cv::INTER_LINEAR);
        
        // 5. Convert to float and normalize (1/255) on GPU
        cv::cuda::GpuMat gpu_float;
        gpu_resized.convertTo(gpu_float, CV_32FC3, 1.0/255.0);
        
        // 6. Download from GPU to CPU
        cv::Mat cpu_normalized;
        gpu_float.download(cpu_normalized);
        
        // 7. Convert HWC -> CHW (NCHW layout) using blobFromImage
        // Since we already normalized, use scalefactor=1.0
        cv::Mat blob;
        cv::dnn::blobFromImage(cpu_normalized, blob, 1.0, cv::Size(640, 640), 
                               cv::Scalar(), false, false, CV_32F);
        
        // 8. Copy to output buffer
        std::memcpy(out_data, blob.data, blob.total() * blob.elemSize());
        
        #else
        // ========================================
        // CPU fallback preprocessing path
        // ========================================
        static bool first_call = true;
        static int frame_count = 0;
        
        if (first_call) {
            std::cout << "[CPU-PREPROCESS] ========================================" << std::endl;
            std::cout << "[CPU-PREPROCESS] ⚠ Using CPU for image preprocessing" << std::endl;
            std::cout << "[CPU-PREPROCESS] Reason: OpenCV CUDA modules not available" << std::endl;
            std::cout << "[CPU-PREPROCESS] - RGBA->RGB conversion: CPU" << std::endl;
            std::cout << "[CPU-PREPROCESS] - Resize to 640x640: CPU" << std::endl;
            std::cout << "[CPU-PREPROCESS] - Normalize (0-255 -> 0-1): CPU" << std::endl;
            std::cout << "[CPU-PREPROCESS] ========================================" << std::endl;
            first_call = false;
        }
        
        frame_count++;
        if (frame_count % 100 == 0) {
            std::cout << "[CPU-PREPROCESS] Processed " << frame_count << " frames on CPU" << std::endl;
        }
        
        cv::Mat input_rgba(height, width, CV_8UC4, in_data);
        cv::Mat input_rgb;
        cv::cvtColor(input_rgba, input_rgb, cv::COLOR_RGBA2RGB);
        
        // blobFromImage handles resize, normalize, and HWC->CHW conversion
        cv::Mat blob;
        cv::dnn::blobFromImage(input_rgb, blob, 1.0/255.0, cv::Size(640, 640), 
                               cv::Scalar(), false, false, CV_32F);
        
        std::memcpy(out_data, blob.data, blob.total() * blob.elemSize());
        #endif
        
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "[Native] PreprocessImage failed: " << e.what() << std::endl;
        return 1;
    }
}

// ==========================================
// GPU-ONLY Preprocessing (Zero-Copy to ONNX CUDA EP)
// ==========================================
// Takes a GpuMat RGBA, preprocesses on GPU, outputs CUDA tensor pointer
// Note: CHW conversion currently uses CPU as cv::cuda::split is not available in all OpenCV builds
// This is still mostly GPU-based (resize/normalize on GPU)

bool PreprocessImageGpu(const cv::cuda::GpuMat& rgba_gpu, float** out_cuda_ptr, 
                        cv::cuda::GpuMat& temp_buffer) {
    try {
        #ifdef HAVE_OPENCV_CUDAIMGPROC
        // 1. Convert RGBA -> RGB on GPU
        cv::cuda::GpuMat gpu_rgb;
        cv::cuda::cvtColor(rgba_gpu, gpu_rgb, cv::COLOR_RGBA2RGB);
        
        // 2. Resize to 640x640 on GPU
        cv::cuda::GpuMat gpu_resized;
        cv::cuda::resize(gpu_rgb, gpu_resized, cv::Size(640, 640), 0, 0, cv::INTER_LINEAR);
        
        // 3. Convert to float and normalize (1/255) on GPU
        cv::cuda::GpuMat gpu_float;
        gpu_resized.convertTo(gpu_float, CV_32FC3, 1.0/255.0);
        
        // 4. Download for CHW conversion (CPU - fast for small 640x640 image)
        cv::Mat cpu_float;
        gpu_float.download(cpu_float);
        
        // 5. HWC -> CHW conversion using blobFromImage (optimized)
        cv::Mat blob;
        cv::dnn::blobFromImage(cpu_float, blob, 1.0, cv::Size(640, 640), 
                               cv::Scalar(), false, false, CV_32F);
        
        // 6. Upload CHW data back to GPU for ONNX CUDA EP
        temp_buffer.upload(blob.reshape(1, 1));  // 1D row: 1 x (3*640*640)
        
        *out_cuda_ptr = reinterpret_cast<float*>(temp_buffer.data);
        
        // DEBUG: Log first successful GPU preprocess
        static int gpu_prep_count = 0;
        if (gpu_prep_count < 3) {
            std::cout << "[GPU-PREPROCESS] ✓ Hybrid GPU preprocessing complete (resize/normalize on GPU)" << std::endl;
            gpu_prep_count++;
        }
        
        return true;
        
        #else
        std::cerr << "[GPU-PREPROCESS] OpenCV CUDA modules not available" << std::endl;
        return false;
        #endif
        
    } catch (const std::exception& e) {
        std::cerr << "[GPU-PREPROCESS] Failed: " << e.what() << std::endl;
        return false;
    }
}

void ReleaseSession(int64_t session_id) {
    std::lock_guard<std::mutex> lock(g_contexts_mutex);
    g_contexts.erase(session_id);
    std::cout << "[Native] Session " << session_id << " released." << std::endl;
}

// ==========================================
// SHUTDOWN - Must be called before app exit!
// ==========================================
// This releases all GPU resources in the correct order:
// 1. Release all video contexts (CUDA HW decoder contexts)
// 2. Release all ONNX sessions (CUDA tensors/memory)
// 3. Destroy global ONNX environment
// This prevents "CUDA driver shutting down" crashes on exit.

extern "C" __attribute__((visibility("default"))) __attribute__((used))
void Inference_Shutdown() {
    // Guard against double-shutdown
    bool expected = false;
    if (!g_shutdown_called.compare_exchange_strong(expected, true)) {
        // Already shutting down or shut down
        return;
    }
    
    std::cout << "[Native] Shutdown: Releasing GPU resources..." << std::endl;
    
    // 1. Release all video contexts first (they hold CUDA HW decoder buffers)
    {
        std::lock_guard<std::mutex> lock(g_video_mutex);
        int video_count = g_video_contexts.size();
        for (auto& pair : g_video_contexts) {
            auto& ctx = pair.second;
#ifdef USE_FFMPEG_NVDEC
            if (ctx->sws_ctx) {
                sws_freeContext(ctx->sws_ctx);
                ctx->sws_ctx = nullptr;
            }
            if (ctx->packet) {
                av_packet_free(&ctx->packet);
            }
            if (ctx->frame) {
                av_frame_free(&ctx->frame);
            }
            if (ctx->sw_frame) {
                av_frame_free(&ctx->sw_frame);
            }
            if (ctx->codec_ctx) {
                avcodec_free_context(&ctx->codec_ctx);
            }
            if (ctx->hw_device_ctx) {
                av_buffer_unref(&ctx->hw_device_ctx);
            }
            if (ctx->format_ctx) {
                avformat_close_input(&ctx->format_ctx);
            }
            // Clear GPU mats
            ctx->last_rgba_gpu.release();
#endif
        }
        g_video_contexts.clear();
        std::cout << "[Native] ✓ Released " << video_count << " video contexts" << std::endl;
    }
    
    // 2. Release all ONNX sessions (they hold CUDA memory for tensors)
    {
        std::lock_guard<std::mutex> lock(g_contexts_mutex);
        int session_count = g_contexts.size();
        for (auto& pair : g_contexts) {
            auto& ctx = pair.second;
            // Clear tensors first
            ctx->input_tensors.clear();
            ctx->output_tensors.clear();
            // Release CUDA tensor if allocated
            if (ctx->cuda_tensor_ptr) {
#ifdef USE_CUDA
                cudaFree(ctx->cuda_tensor_ptr);
#endif
                ctx->cuda_tensor_ptr = nullptr;
            }
            // Release GPU preprocess buffer
            ctx->gpu_preprocess_buffer.release();
            // Session destructor will handle ONNX cleanup
            ctx->session.reset();
        }
        g_contexts.clear();
        std::cout << "[Native] ✓ Released " << session_count << " ONNX sessions" << std::endl;
    }
    
    // 3. Destroy global environment (must be last)
    {
        std::lock_guard<std::mutex> lock(g_env_mutex);
        g_allocator.reset();
        g_env.reset();
        std::cout << "[Native] ✓ Destroyed global ONNX environment" << std::endl;
    }
    
    // 4. Synchronize CUDA to ensure all operations complete
#ifdef USE_CUDA
    cudaDeviceSynchronize();
    std::cout << "[Native] ✓ CUDA synchronized" << std::endl;
#endif
    
    std::cout << "[Native] Shutdown complete - safe to exit" << std::endl;
}


// Force immediate process termination bypassing static destructors
// This is necessary because ONNX Runtime's static destructors run after
// CUDA driver shutdown starts, causing crashes.
extern "C" __attribute__((visibility("default"))) __attribute__((used))
void Native_ForceExit() {
    std::cout << "[Native] Force Exit requested - calling _Exit(0)" << std::endl;
    // Ensure all streams are flushed
    std::cout.flush();
    std::cerr.flush();
    // Immediate termination
    std::_Exit(0);
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
    std::cout << "[NVDEC] ========================================" << std::endl;
    std::cout << "[NVDEC] Opening video: " << url << std::endl;
    
    std::lock_guard<std::mutex> lock(g_video_mutex);
    
    try {
#ifdef USE_FFMPEG_NVDEC
        auto ctx = std::make_shared<VideoContext>();
        
        // 1. Allocate format context
        ctx->format_ctx = avformat_alloc_context();
        
        // 2. Configure RTSP-specific options for reliable streaming
        AVDictionary* options = nullptr;
        std::string url_str(url);
        
        if (url_str.find("rtsp://") == 0) {
            std::cout << "[NVDEC] RTSP stream detected, configuring for reliability..." << std::endl;
            
            // Use TCP instead of UDP to avoid packet loss/distortion
            av_dict_set(&options, "rtsp_transport", "tcp", 0);
            std::cout << "[NVDEC]   - Transport: TCP (prevents packet loss)" << std::endl;
            
            // Set buffer size to handle network jitter
            av_dict_set(&options, "buffer_size", "4096000", 0);  // 4MB buffer
            std::cout << "[NVDEC]   - Buffer: 4MB" << std::endl;
            
            // Reduce latency - don't wait for all streams to start
            av_dict_set(&options, "max_delay", "500000", 0);  // 0.5 seconds
            
            // Allow discarding corrupted frames instead of failing
            av_dict_set(&options, "fflags", "discardcorrupt", 0);
            std::cout << "[NVDEC]   - Discard corrupt frames: enabled" << std::endl;
            
            // Set timeout to avoid hanging on connection issues
            av_dict_set(&options, "stimeout", "5000000", 0);  // 5 seconds
            
            // For low-latency streaming, don't analyze too long
            av_dict_set(&options, "analyzeduration", "500000", 0);  // 0.5s
            av_dict_set(&options, "probesize", "500000", 0);  // 500KB
        }
        
        // 3. Open input stream with options
        if (avformat_open_input(&ctx->format_ctx, url, nullptr, &options) < 0) {
            std::cerr << "[NVDEC] ❌ Failed to open input: " << url << std::endl;
            if (options) av_dict_free(&options);
            return 0;
        }
        
        // Free options after use
        if (options) av_dict_free(&options);
        
        // 2. Retrieve stream information
        if (avformat_find_stream_info(ctx->format_ctx, nullptr) < 0) {
            std::cerr << "[NVDEC] ❌ Failed to find stream info" << std::endl;
            avformat_close_input(&ctx->format_ctx);
            return 0;
        }
        
        // 3. Find video stream
        ctx->video_stream_idx = -1;
        for (unsigned int i = 0; i < ctx->format_ctx->nb_streams; i++) {
            if (ctx->format_ctx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
                ctx->video_stream_idx = i;
                break;
            }
        }
        
        if (ctx->video_stream_idx == -1) {
            std::cerr << "[NVDEC] ❌ No video stream found" << std::endl;
            avformat_close_input(&ctx->format_ctx);
            return 0;
        }
        
        AVCodecParameters* codecpar = ctx->format_ctx->streams[ctx->video_stream_idx]->codecpar;
        
        // 4. Determine correct NVDEC decoder based on codec
        const char* decoder_name = nullptr;
        switch (codecpar->codec_id) {
            case AV_CODEC_ID_H264:
                decoder_name = "h264_cuvid";
                std::cout << "[NVDEC] Codec: H.264, using h264_cuvid decoder" << std::endl;
                break;
            case AV_CODEC_ID_HEVC:
                decoder_name = "hevc_cuvid";
                std::cout << "[NVDEC] Codec: HEVC/H.265, using hevc_cuvid decoder" << std::endl;
                break;
            case AV_CODEC_ID_VP9:
                decoder_name = "vp9_cuvid";
                std::cout << "[NVDEC] Codec: VP9, using vp9_cuvid decoder" << std::endl;
                break;
            case AV_CODEC_ID_AV1:
                decoder_name = "av1_cuvid";
                std::cout << "[NVDEC] Codec: AV1, using av1_cuvid decoder" << std::endl;
                break;
            default:
                std::cerr << "[NVDEC] ❌ Unsupported codec ID: " << codecpar->codec_id << std::endl;
                std::cerr << "[NVDEC] ⚠ Supported codecs: H.264, HEVC, VP9, AV1" << std::endl;
                avformat_close_input(&ctx->format_ctx);
                return 0;
        }
        
        // 5. Find the hardware decoder
        const AVCodec* decoder = avcodec_find_decoder_by_name(decoder_name);
        if (!decoder) {
            std::cerr << "[NVDEC] ❌ Decoder " << decoder_name << " not found!" << std::endl;
            std::cerr << "[NVDEC] ⚠ Make sure FFmpeg is compiled with --enable-nvdec --enable-cuda" << std::endl;
            avformat_close_input(&ctx->format_ctx);
            return 0;
        }
        
        std::cout << "[NVDEC] ✓ Found decoder: " << decoder->long_name << std::endl;
        
        // 6. Create codec context
        ctx->codec_ctx = avcodec_alloc_context3(decoder);
        if (!ctx->codec_ctx) {
            std::cerr << "[NVDEC] ❌ Failed to allocate codec context" << std::endl;
            avformat_close_input(&ctx->format_ctx);
            return 0;
        }
        
        if (avcodec_parameters_to_context(ctx->codec_ctx, codecpar) < 0) {
            std::cerr << "[NVDEC] ❌ Failed to copy codec parameters" << std::endl;
            avcodec_free_context(&ctx->codec_ctx);
            avformat_close_input(&ctx->format_ctx);
            return 0;
        }
        
        // 7. Create CUDA hardware device context
        if (av_hwdevice_ctx_create(&ctx->hw_device_ctx, AV_HWDEVICE_TYPE_CUDA, nullptr, nullptr, 0) < 0) {
            std::cerr << "[NVDEC] ❌ Failed to create CUDA device context" << std::endl;
            std::cerr << "[NVDEC] ⚠ Make sure CUDA drivers are installed" << std::endl;
            avcodec_free_context(&ctx->codec_ctx);
            avformat_close_input(&ctx->format_ctx);
            return 0;
        }
        
        std::cout << "[NVDEC] ✓ Created CUDA hardware device context" << std::endl;
        
        // 8. Assign hardware device context to codec
        ctx->codec_ctx->hw_device_ctx = av_buffer_ref(ctx->hw_device_ctx);
        
        // 9. Open codec
        if (avcodec_open2(ctx->codec_ctx, decoder, nullptr) < 0) {
            std::cerr << "[NVDEC] ❌ Failed to open decoder" << std::endl;
            av_buffer_unref(&ctx->hw_device_ctx);
            avcodec_free_context(&ctx->codec_ctx);
            avformat_close_input(&ctx->format_ctx);
            return 0;
        }
        
        std::cout << "[NVDEC] ✓ Decoder opened successfully" << std::endl;
        
        // 10. Allocate frames and packet
        ctx->frame = av_frame_alloc();
        ctx->sw_frame = av_frame_alloc();
        ctx->packet = av_packet_alloc();
        
        if (!ctx->frame || !ctx->sw_frame || !ctx->packet) {
            std::cerr << "[NVDEC] ❌ Failed to allocate frames/packet" << std::endl;
            if (ctx->frame) av_frame_free(&ctx->frame);
            if (ctx->sw_frame) av_frame_free(&ctx->sw_frame);
            if (ctx->packet) av_packet_free(&ctx->packet);
            av_buffer_unref(&ctx->hw_device_ctx);
            avcodec_free_context(&ctx->codec_ctx);
            avformat_close_input(&ctx->format_ctx);
            return 0;
        }
        
        // Store video properties
        ctx->width = ctx->codec_ctx->width;
        ctx->height = ctx->codec_ctx->height;
        
        // GPU textures will be created LAZILY on first frame (when GL context exists)
        ctx->texture_id = 0;  // Not created yet
        ctx->use_gpu_texture = true;  // Enable lazy creation
        
        std::cout << "[GPU-TEXTURE] Lazy texture creation enabled for stream (" 
                  << ctx->codec_ctx->width << "x" << ctx->codec_ctx->height << ")" << std::endl;
        
        int64_t id = g_next_video_id++;
        g_video_contexts[id] = ctx;
        
        std::cout << "[NVDEC] ========================================" << std::endl;
        std::cout << "[NVDEC] ✓ Hardware decoder initialized successfully" << std::endl;
        std::cout << "[NVDEC]   Video ID: " << id << std::endl;
        std::cout << "[NVDEC]   Resolution: " << ctx->width << "x" << ctx->height << std::endl;
        std::cout << "[NVDEC]   Decoder: " << decoder_name << std::endl;
        std::cout << "[NVDEC] ----------------------------------------" << std::endl;
        std::cout << "[NVDEC] 🎯 GPU decoding with NVDEC is ACTIVE" << std::endl;
        std::cout << "[NVDEC] ✓ Verify with: watch -n 1 nvidia-smi dmon -s u" << std::endl;
        std::cout << "[NVDEC]   The 'dec' column should show > 0" << std::endl;
        std::cout << "[NVDEC] ========================================" << std::endl;
        
        return id;
        
#else
        // Fallback to OpenCV if FFmpeg NVDEC not available
        std::cout << "[VIDEO] ⚠ FFmpeg NVDEC not compiled, using OpenCV fallback" << std::endl;
        
        setenv("OPENCV_FFMPEG_CAPTURE_OPTIONS", "hwaccel;auto", 0);
        auto cap = std::make_unique<cv::VideoCapture>(url, cv::CAP_FFMPEG);
        
        if (!cap->isOpened()) {
            std::cerr << "[VIDEO] ❌ Failed to open video" << std::endl;
            return 0;
        }
        
        auto ctx = std::make_shared<VideoContext>();
        ctx->cap = std::move(cap);
        
        int64_t id = g_next_video_id++;
        g_video_contexts[id] = ctx;
        
        std::cout << "[VIDEO] Video opened with OpenCV (CPU decode)" << std::endl;
        return id;
#endif
        
    } catch (const std::exception& e) {
        std::cerr << "[NVDEC] ❌ Exception: " << e.what() << std::endl;
        return 0;
    }
}

void Video_Release(int64_t video_id) {
    std::lock_guard<std::mutex> lock(g_video_mutex);
    
#ifdef USE_FFMPEG_NVDEC
    auto it = g_video_contexts.find(video_id);
    if (it != g_video_contexts.end()) {
        auto& ctx = it->second;
        
        // Clean up FFmpeg resources
        if (ctx->sws_ctx) {
            sws_freeContext(ctx->sws_ctx);
        }
        if (ctx->packet) {
            av_packet_free(&ctx->packet);
        }
        if (ctx->frame) {
            av_frame_free(&ctx->frame);
        }
        if (ctx->sw_frame) {
            av_frame_free(&ctx->sw_frame);
        }
        if (ctx->codec_ctx) {
            avcodec_free_context(&ctx->codec_ctx);
        }
        if (ctx->hw_device_ctx) {
            av_buffer_unref(&ctx->hw_device_ctx);
        }
        if (ctx->format_ctx) {
            avformat_close_input(&ctx->format_ctx);
        }
        
        std::cout << "[NVDEC] Released video ID: " << video_id << std::endl;
    }
#endif
    
    g_video_contexts.erase(video_id);
}

int Video_GetFrame(int64_t video_id, uint8_t** out_buffer, int* width, int* height, int64_t* out_timestamp) {
    std::shared_ptr<VideoContext> ctx;
    {
        std::lock_guard<std::mutex> lock(g_video_mutex);
        auto it = g_video_contexts.find(video_id);
        if (it == g_video_contexts.end()) {
             std::cerr << "[NVDEC] GetFrame: Invalid ID " << video_id << std::endl;
             return 1; 
        }
        ctx = it->second;
    }
    
    // Lock only THIS video during frame capture
    std::lock_guard<std::mutex> lock(ctx->mutex);
    
    int64_t timestamp = 0;

#ifdef USE_FFMPEG_NVDEC
    // Track frame decode statistics
    static std::map<int64_t, int> frame_counts;
    if (frame_counts.find(video_id) == frame_counts.end()) {
        frame_counts[video_id] = 0;
    }
    
    // Read frames until we get a video frame
    while (true) {
        int ret = av_read_frame(ctx->format_ctx, ctx->packet);
        
        // Handle EOF - loop video (for files, not RTSP)
        if (ret == AVERROR_EOF) {
            // Check if this is a file (not a stream)
            if (ctx->format_ctx->pb && ctx->format_ctx->pb->seekable) {
                // Seek back to beginning
                av_seek_frame(ctx->format_ctx, ctx->video_stream_idx, 0, AVSEEK_FLAG_BACKWARD);
                avcodec_flush_buffers(ctx->codec_ctx);
                ctx->first_frame_read = false; // Reset sync
                std::cout << "[NVDEC] Video ID " << video_id << ": Looped back to start" << std::endl;
                continue;
            } else {
                // Stream ended, can't loop
                std::cerr << "[NVDEC] Stream ended" << std::endl;
                return 2;
            }
        }
        
        if (ret < 0) {
            char err_buf[AV_ERROR_MAX_STRING_SIZE];
            av_strerror(ret, err_buf, sizeof(err_buf));
            std::cerr << "[NVDEC] Error reading frame: " << err_buf << std::endl;
            
            // For RTSP streams, try to recover from errors
            if (ctx->format_ctx->pb && !ctx->format_ctx->pb->seekable) {
                std::cout << "[NVDEC] RTSP error, attempting to continue..." << std::endl;
                continue;
            }
            return 2;
        }
        
        // Skip non-video packets
        if (ctx->packet->stream_index != ctx->video_stream_idx) {
            av_packet_unref(ctx->packet);
            continue;
        }
        
        // Send packet to decoder
        ret = avcodec_send_packet(ctx->codec_ctx, ctx->packet);
        av_packet_unref(ctx->packet);
        
        if (ret < 0) {
            std::cerr << "[NVDEC] Error sending packet to decoder" << std::endl;
            continue;
        }
        
        // Receive decoded frame
        ret = avcodec_receive_frame(ctx->codec_ctx, ctx->frame);
        if (ret == AVERROR(EAGAIN)) {
            // Need more packets
            continue;
        } else if (ret < 0) {
            std::cerr << "[NVDEC] Error receiving frame from decoder" << std::endl;
            continue;  // Try to continue instead of failing
        }
        
        // Successfully got a frame
        
        // ==========================================
        // FRAME SKIPPING FOR REAL-TIME SYNC
        // ==========================================
        
        // Extract Timestamp (PTS in milliseconds)
        // int64_t timestamp = 0; // Declared at top
        if (ctx->frame->pts != AV_NOPTS_VALUE) {
            // Convert PTS to milliseconds based on time base
            if (ctx->format_ctx->streams[ctx->video_stream_idx]->time_base.den > 0) {
                 timestamp = (int64_t)(ctx->frame->pts * av_q2d(ctx->format_ctx->streams[ctx->video_stream_idx]->time_base) * 1000);
            } else {
                 timestamp = ctx->frame->pts;
            }
        } else {
            timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::system_clock::now().time_since_epoch()
            ).count();
        }

        if (!ctx->first_frame_read) {
            ctx->start_time = std::chrono::steady_clock::now();
            ctx->start_pts = timestamp;
            ctx->first_frame_read = true;
        } else {
            // Check lag
            auto now = std::chrono::steady_clock::now();
            auto elapsed_wall_ms = std::chrono::duration_cast<std::chrono::milliseconds>(now - ctx->start_time).count();
            auto elapsed_video_ms = timestamp - ctx->start_pts;
            
            // Allow 50ms buffer (framerate tolerance)
            // If Video is BEHIND Wall Clock by > 50ms, SKIP IT
            if (elapsed_video_ms < (elapsed_wall_ms - 50)) {
                 std::cout << "[NVDEC] Skipping frame (Video: " << elapsed_video_ms << "ms, Wall: " << elapsed_wall_ms 
                           << "ms, Lag: " << (elapsed_wall_ms - elapsed_video_ms) << "ms)" << std::endl;
                 // Don't count skipped frames for stats to avoid spam
                 av_frame_unref(ctx->frame);
                 continue; // Loop to get next frame
            }
        }
        
        break; // Keep this frame
    }
    
    // REMOVED: Buffer catch-up logic to stabilize decode time
    // The catch-up mechanism was causing 100-150ms decode spikes when streams fell behind
    // Trade-off: Prioritize consistent low latency over buffering resilience
    
    frame_counts[video_id]++;
    
    // Log every 100 frames
    if (frame_counts[video_id] % 100 == 0) {
        std::cout << "[NVDEC] Video ID " << video_id << ": Decoded " 
                  << frame_counts[video_id] << " frames (GPU)" << std::endl;
    }
    
    // Timestamp already calculated above
    if (out_timestamp) *out_timestamp = timestamp;

    // ========================================
    // ZERO-COPY GPU TEXTURE RENDERING PATH
    // ========================================
    if (ctx->use_gpu_texture && (ctx->texture_id > 0 || ctx->texture_manager_id > 0)) {
        
        // NVDEC outputs NV12 in CUDA memory (ctx->frame is AV_PIX_FMT_CUDA)
        // Goal: Keep everything on GPU, no CPU downloads for display!
        
        int src_width = ctx->frame->width;
        int src_height = ctx->frame->height;
        
        try {
            cv::cuda::GpuMat rgba_gpu;
            
#ifdef USE_NPP
            // ... (NPP conversion same as before)
            // ========================================
            // GPU-NATIVE NV12 -> RGBA CONVERSION (NPP)
            // ========================================
            // Keep frames in CUDA memory - no CPU roundtrip!
            
            static bool npp_logged = false;
            if (!npp_logged) {
                std::cout << "[NPP] ✓ Using GPU-native NV12 to RGBA conversion" << std::endl;
                npp_logged = true;
            }
            
            if (ctx->frame->format == AV_PIX_FMT_CUDA) {
                int frame_w = ctx->frame->width;
                int frame_h = ctx->frame->height;
                
                // Allocate GPU buffers
                cv::cuda::GpuMat rgb_gpu(frame_h, frame_w, CV_8UC3);
                rgba_gpu.create(frame_h, frame_w, CV_8UC4);
                
                const Npp8u* pSrc[2] = {
                    (const Npp8u*)ctx->frame->data[0],
                    (const Npp8u*)ctx->frame->data[1]
                };
                int nSrcStep = ctx->frame->linesize[0];
                NppiSize oSizeROI = {frame_w, frame_h};
                
                NppStatus npp_status = nppiNV12ToRGB_8u_P2C3R(
                    pSrc, nSrcStep,
                    rgb_gpu.ptr<Npp8u>(), (int)rgb_gpu.step,
                    oSizeROI
                );
                
                if (npp_status != NPP_SUCCESS) {
                    goto cpu_fallback;
                }
                
                cv::cuda::cvtColor(rgb_gpu, rgba_gpu, cv::COLOR_RGB2RGBA);
                
            } else {
                goto cpu_fallback;
            }
            
            goto npp_done;
            
cpu_fallback:
#endif
            {
                // ... (CPU fallback same as before)
                // ========================================
                // NV12 -> RGBA CONVERSION (CPU Fallback)
                // ========================================
                
                AVFrame* frame_to_convert = nullptr;
                if (ctx->frame->format == AV_PIX_FMT_CUDA) {
                    if (av_hwframe_transfer_data(ctx->sw_frame, ctx->frame, 0) < 0) {
                         av_frame_unref(ctx->frame);
                         return 2;
                    }
                    frame_to_convert = ctx->sw_frame;
                } else {
                    frame_to_convert = ctx->frame;
                }
                
                int frame_w = frame_to_convert->width;
                int frame_h = frame_to_convert->height;
                int y_stride = frame_to_convert->linesize[0];
                int uv_stride = frame_to_convert->linesize[1];
                int uv_height = frame_h / 2;
                
                int nv12_size = frame_w * (frame_h + uv_height);
                if (ctx->nv12_buffer.size() != nv12_size) ctx->nv12_buffer.resize(nv12_size);
                
                for (int i = 0; i < frame_h; i++) {
                    memcpy(ctx->nv12_buffer.data() + i * frame_w, 
                           frame_to_convert->data[0] + i * y_stride, frame_w);
                }
                for (int i = 0; i < uv_height; i++) {
                    memcpy(ctx->nv12_buffer.data() + frame_w * frame_h + i * frame_w, 
                           frame_to_convert->data[1] + i * uv_stride, frame_w);
                }
                
                cv::Mat nv12_cpu(frame_h + uv_height, frame_w, CV_8UC1, ctx->nv12_buffer.data());
                cv::Mat rgba_cpu;
                cv::cvtColor(nv12_cpu, rgba_cpu, cv::COLOR_YUV2RGBA_NV12);
                rgba_gpu.upload(rgba_cpu);
            }
            
#ifdef USE_NPP
npp_done:
#endif
            
            // Upload OpenGL texture via CUDA-GL interop (zero-copy!)
            // PASS TIMESTAMP for strict synchronization
            int tex_id = ctx->texture_manager_id > 0 ? ctx->texture_manager_id : ctx->texture_id;
            texture_manager::TextureManager::getInstance().setPendingGpuFrame(tex_id, rgba_gpu, timestamp);
            
            // Store GPU frame for GPU inference path (zero-copy!)
            ctx->last_rgba_gpu = rgba_gpu;
            ctx->has_gpu_frame = true;
            
            // Legacy path: Download RGBA to CPU buffer for Dart-side
            int rgba_size = rgba_gpu.cols * rgba_gpu.rows * 4;
            if (ctx->rgba_buffer.size() != rgba_size) {
                ctx->rgba_buffer.resize(rgba_size);
            }
            
            if (ctx->texture_manager_id == 0 && ctx->texture_id == 0) {
                cv::Mat rgba_cpu_for_legacy(rgba_gpu.rows, rgba_gpu.cols, CV_8UC4, ctx->rgba_buffer.data());
                rgba_gpu.download(rgba_cpu_for_legacy);
            }
            
            av_frame_unref(ctx->frame);
            
            *width = src_width;
            *height = src_height;
            *out_buffer = ctx->rgba_buffer.data();
            
            return 0; // Success
            
        } catch (const cv::Exception& e) {
            std::cerr << "[ZERO-COPY-ERROR] " << e.what() << std::endl;
            ctx->use_gpu_texture = false;
        }
    }
    
    // ... (Remainder of existing fallback logic)
    // CPU Path if texture path skipped/failed
    if (ctx->frame->format == AV_PIX_FMT_CUDA) {
        if (av_hwframe_transfer_data(ctx->sw_frame, ctx->frame, 0) < 0) {
            av_frame_unref(ctx->frame);
            return 2;
        }
        av_frame_copy_props(ctx->sw_frame, ctx->frame);
    } else {
        av_frame_unref(ctx->sw_frame);
        av_frame_move_ref(ctx->sw_frame, ctx->frame);
    }
    
    // Convert to RGBA (CPU)
    // ... (sw_scale code) ...
    int src_width = ctx->sw_frame->width;
    int src_height = ctx->sw_frame->height;
    AVPixelFormat src_format = (AVPixelFormat)ctx->sw_frame->format;
    
    int dst_width = src_width;
    int dst_height = src_height;
    if (src_width > 320) {
         float scale = 320.0f / src_width;
         dst_width = 320;
         dst_height = (int)(src_height * scale);
    }
    
    if (!ctx->sws_ctx || dst_width != ctx->last_width || dst_height != ctx->last_height || (int)src_format != ctx->last_format) {
         if (ctx->sws_ctx) sws_freeContext(ctx->sws_ctx);
         ctx->sws_ctx = sws_getContext(src_width, src_height, src_format, dst_width, dst_height, AV_PIX_FMT_RGBA, SWS_FAST_BILINEAR, nullptr, nullptr, nullptr);
         ctx->last_width = dst_width;
         ctx->last_height = dst_height;
         ctx->last_format = (int)src_format;
    }
    
    size_t rgba_size = dst_width * dst_height * 4;
    if (ctx->rgba_buffer.size() != rgba_size) ctx->rgba_buffer.resize(rgba_size);
    
    uint8_t* dst_data[1] = { ctx->rgba_buffer.data() };
    int dst_linesize[1] = { dst_width * 4 };
    
    sws_scale(ctx->sws_ctx, ctx->sw_frame->data, ctx->sw_frame->linesize, 0, src_height, dst_data, dst_linesize);
    
    av_frame_unref(ctx->sw_frame);
    
    *width = dst_width;
    *height = dst_height;
    *out_buffer = ctx->rgba_buffer.data();
    
    return 0;

#else
    // OpenCV Fallback (CPU)
    // ... (OpenCV read code)
    if (out_timestamp) *out_timestamp = (int64_t)ctx->cap->get(cv::CAP_PROP_POS_MSEC);
    
    // ... (Rest of OpenCV logic)
    bool success = ctx->cap->read(ctx->last_frame);
    if (!success || ctx->last_frame.empty()) {
        ctx->cap->set(cv::CAP_PROP_POS_FRAMES, 0);
        success = ctx->cap->read(ctx->last_frame);
        if (!success) return 2;
    }
    
    cv::Mat rgb_frame;
    cv::cvtColor(ctx->last_frame, rgb_frame, cv::COLOR_BGR2RGBA);
    size_t dataSize = rgb_frame.total() * rgb_frame.elemSize();
    if (ctx->rgb_buffer.size() != dataSize) ctx->rgb_buffer.resize(dataSize);
    std::memcpy(ctx->rgb_buffer.data(), rgb_frame.data, dataSize);
    
    *width = rgb_frame.cols;
    *height = rgb_frame.rows;
    *out_buffer = ctx->rgb_buffer.data();
    
    return 0;
#endif
}

// Set the TextureManager ID for a video stream (called from UI thread)
extern "C" __attribute__((visibility("default"))) __attribute__((used))
void Video_SetTextureManagerId(long long session_id, int texture_manager_id) {
    if (session_id <= 0) return;
    
    std::lock_guard<std::mutex> lock(g_contexts_mutex);
    auto it = g_video_contexts.find(session_id);
    if (it != g_video_contexts.end()) {
        std::lock_guard<std::mutex> vid_lock(it->second->mutex);
        it->second->texture_manager_id = texture_manager_id;
        it->second->use_gpu_texture = true; // Enable GPU path
        std::cout << "[BRIDGE] Linked video " << session_id << " to texture manager " << texture_manager_id << std::endl;
    } else {
        std::cerr << "[BRIDGE] Warning: Video context " << session_id << " not found for texture linking" << std::endl;
    }
}

// WRAPPERS FOR SHARED TEXTURE MANAGER (Single Instance Fix)
extern "C" __attribute__((visibility("default"))) __attribute__((used))
int Texture_Create(int width, int height) {
    return texture_manager::TextureManager::getInstance().createTexture(width, height);
}

extern "C" __attribute__((visibility("default"))) __attribute__((used))
uint32_t Texture_GetGLHandle(int texture_id) {
    auto info = texture_manager::TextureManager::getInstance().getTexture(texture_id);
    return info ? info->gl_texture_id : 0;
}

extern "C" __attribute__((visibility("default"))) __attribute__((used))
int Texture_GetDimensions(int texture_id, int* width, int* height) {
    if (texture_manager::TextureManager::getInstance().getTextureDimensions(texture_id, width, height)) {
        return 0;  // Success
    }
    return -1;  // Not found
}

// Upload pending frame to GL texture (MUST be called on UI thread with GL context)
extern "C" __attribute__((visibility("default"))) __attribute__((used))
int Texture_UploadPending(int texture_id) {
    if (texture_manager::TextureManager::getInstance().uploadPendingFrame(texture_id)) {
        return 0;  // Success - frame uploaded
    }
    return -1;  // No pending frame or error
}

// Check if texture has valid frame content (safe to sample)
extern "C" __attribute__((visibility("default"))) __attribute__((used))
int Texture_HasValidFrame(int texture_id) {
    return texture_manager::TextureManager::getInstance().hasValidFrame(texture_id) ? 1 : 0;
}

// Ensure GL texture is created (MUST call from UI thread with GL context)
extern "C" __attribute__((visibility("default"))) __attribute__((used))
int Texture_EnsureGLTexture(int texture_id) {
    return texture_manager::TextureManager::getInstance().ensureGLTexture(texture_id) ? 0 : -1;
}

// Show specific frame (Strict Synchronization)
extern "C" __attribute__((visibility("default"))) __attribute__((used))
int Texture_ShowFrame(int texture_id, int64_t timestamp) {
    if (texture_manager::TextureManager::getInstance().showFrame(texture_id, timestamp)) {
        return 0; // Success
    }
    return -1; // Frame not found/dropped
}


// ==========================================
// Combined Loop (Capture + Infer)
// ==========================================
extern "C" __attribute__((visibility("default"))) __attribute__((used))
int Video_GetFrameAndInfer(
    int64_t video_id, 
    int64_t session_id, 
    const char* input_name,
    const char** output_names, 
    int num_outputs,
    uint8_t** out_frame_buffer,
    int* out_width, 
    int* out_height,
    float* out_inference_time,
    int64_t* out_timestamp
) {
    auto start_time = std::chrono::high_resolution_clock::now();

    // 1. Get Frame
    int64_t timestamp = 0;
    int ret = Video_GetFrame(video_id, out_frame_buffer, out_width, out_height, &timestamp);
    if (ret != 0) return ret; // 2=EOF/Error/Empty
    
    if (out_timestamp) *out_timestamp = timestamp;

    // 2. Get VideoContext to check for GPU frame
    std::shared_ptr<VideoContext> video_ctx;
    {
        std::lock_guard<std::mutex> lock(g_video_mutex);
        auto it = g_video_contexts.find(video_id);
        if (it != g_video_contexts.end()) {
            video_ctx = it->second;
        }
    }

    // 3. Locate Session
    std::shared_ptr<SessionContext> ctx;
    {
        std::lock_guard<std::mutex> lock(g_contexts_mutex);
        auto it = g_contexts.find(session_id);
        if (it == g_contexts.end()) return 10; // Session not found
        ctx = it->second;
    }

    std::lock_guard<std::mutex> lock(ctx->mutex);
    
    // ========================================
    // GPU INFERENCE PATH (Full Zero-Copy)
    // ========================================
    #ifdef HAVE_OPENCV_CUDAIMGPROC
    if (video_ctx && video_ctx->has_gpu_frame && !video_ctx->last_rgba_gpu.empty()) {
        // Use GPU preprocessing and CUDA tensor
        float* cuda_tensor_ptr = nullptr;
        
        if (PreprocessImageGpu(video_ctx->last_rgba_gpu, &cuda_tensor_ptr, ctx->gpu_preprocess_buffer)) {
            try {
                // Create CUDA memory info for ONNX tensor
                Ort::MemoryInfo cuda_mem_info("Cuda", OrtDeviceAllocator, 0, OrtMemTypeDefault);
                int64_t input_dims[] = {1, 3, 640, 640};
                size_t tensor_size = 1 * 3 * 640 * 640;
                
                ctx->input_name_strings.clear();
                ctx->input_tensors.clear();
                ctx->input_name_strings.push_back(std::string(input_name));
                
                // Create tensor from CUDA device pointer (ZERO COPY!)
                Ort::Value tensor = Ort::Value::CreateTensor<float>(
                    cuda_mem_info, 
                    cuda_tensor_ptr, 
                    tensor_size, 
                    input_dims, 
                    4
                );
                
                ctx->input_tensors.push_back(std::move(tensor));
                
                // Run Inference (now on GPU!)
                std::vector<const char*> input_names_ptrs;
                input_names_ptrs.push_back(ctx->input_name_strings[0].c_str());

                ctx->output_tensors = ctx->session->Run(
                    Ort::RunOptions{nullptr}, 
                    input_names_ptrs.data(), 
                    ctx->input_tensors.data(), 
                    ctx->input_tensors.size(), 
                    output_names, 
                    num_outputs
                );

                auto end_time = std::chrono::high_resolution_clock::now();
                std::chrono::duration<float, std::milli> duration = end_time - start_time;
                if (out_inference_time) *out_inference_time = duration.count();
                
                // DEBUG: Log first few GPU inferences
                static int gpu_infer_count = 0;
                if (gpu_infer_count < 3) {
                    std::cout << "[GPU-INFER] ✓ Full GPU inference complete in " 
                              << duration.count() << "ms (zero CPU copy!)" << std::endl;
                    gpu_infer_count++;
                }
                
                return 0;
                
            } catch (const std::exception& e) {
                std::cerr << "[GPU-INFER] CUDA tensor inference failed: " << e.what() 
                          << " - falling back to CPU" << std::endl;
                // Fall through to CPU path
            }
        }
    }
    #endif
    
    // ========================================
    // CPU INFERENCE PATH (Fallback)
    // ========================================
    size_t required_size = 1 * 3 * 640 * 640;
    if (ctx->preprocess_buffer.size() != required_size) {
        ctx->preprocess_buffer.resize(required_size);
    }
    
    ret = PreprocessImage(*out_frame_buffer, *out_width, *out_height, ctx->preprocess_buffer.data());
    if (ret != 0) return 11; // Preprocess failed

    try {
        Ort::MemoryInfo memory_info = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
        int64_t input_dims[] = {1, 3, 640, 640};
        
        ctx->input_name_strings.clear();
        ctx->input_tensors.clear();
        ctx->input_name_strings.push_back(std::string(input_name));
        
        Ort::Value tensor = Ort::Value::CreateTensor<float>(
            memory_info, 
            ctx->preprocess_buffer.data(), 
            required_size, 
            input_dims, 
            4
        );
        
        ctx->input_tensors.push_back(std::move(tensor));
        
        std::vector<const char*> input_names_ptrs;
        input_names_ptrs.push_back(ctx->input_name_strings[0].c_str());

        ctx->output_tensors = ctx->session->Run(
            Ort::RunOptions{nullptr}, 
            input_names_ptrs.data(), 
            ctx->input_tensors.data(), 
            ctx->input_tensors.size(), 
            output_names, 
            num_outputs
        );

        auto end_time = std::chrono::high_resolution_clock::now();
        std::chrono::duration<float, std::milli> duration = end_time - start_time;
        if (out_inference_time) *out_inference_time = duration.count();
        
        return 0;

    } catch (const std::exception& e) {
        std::cerr << "[Native] Loop Infer failed: " << e.what() << std::endl;
        return 12;
    }
}

// Static storage for labels string (to keep memory valid after function returns)
static std::map<int64_t, std::string> g_labels_cache;

int Session_GetLabels(int64_t session_id, const char** out_labels, int* out_length) {
    std::shared_ptr<SessionContext> ctx;
    {
        std::lock_guard<std::mutex> lock(g_contexts_mutex);
        auto it = g_contexts.find(session_id);
        if (it == g_contexts.end()) {
            *out_labels = nullptr;
            *out_length = 0;
            return 1;
        }
        ctx = it->second;
    }

    std::lock_guard<std::mutex> lock(ctx->mutex);
    
    try {
        Ort::AllocatorWithDefaultOptions allocator;
        auto metadata = ctx->session->GetModelMetadata();
        
        // Try common keys used by YOLO models for class labels
        // YOLO/Ultralytics typically uses "names" as a Python dict string like: {0: 'person', 1: 'bicycle', ...}
        const char* keys_to_try[] = {"names", "labels", "class_names", "classes"};
        std::string labels_str;
        
        for (const char* key : keys_to_try) {
            auto value_ptr = metadata.LookupCustomMetadataMapAllocated(key, allocator);
            if (value_ptr) {
                labels_str = std::string(value_ptr.get());
                std::cout << "[Native] Found metadata key '" << key << "': " << labels_str.substr(0, 100) << "..." << std::endl;
                break;
            }
        }
        
        if (labels_str.empty()) {
            // No labels found in metadata
            std::cout << "[Native] No label metadata found in model" << std::endl;
            *out_labels = nullptr;
            *out_length = 0;
            return 0; // Not an error, just no labels
        }
        
        // Store in cache for this session
        g_labels_cache[session_id] = labels_str;
        *out_labels = g_labels_cache[session_id].c_str();
        *out_length = (int)g_labels_cache[session_id].length();
        
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "[Native] GetLabels failed: " << e.what() << std::endl;
        *out_labels = nullptr;
        *out_length = 0;
        return 2;
    }
}
