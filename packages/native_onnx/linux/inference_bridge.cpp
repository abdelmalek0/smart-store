#include "inference_bridge.h"
#include "inference_manager.h"
#include "video_manager.h"
#include "image_processor.h"
#include "texture_manager.h"

#include <unistd.h>
#include <iostream>
#include <vector>
#include <algorithm>
#include <csignal>
#include <atomic>
#include <cstring>
#include <map>

// Shutdown state for signal handler
static std::atomic<bool> g_local_shutdown_requested{false};

static void signal_handler(int signum) {
    if (!g_local_shutdown_requested.load()) {
        const char* msg = "\n[Native] Signal received - cleaning up...\n";
        write(STDERR_FILENO, msg, strlen(msg));
        g_local_shutdown_requested.store(true);
    }
    // Re-raise signal with default handler to exit
    signal(signum, SIG_DFL);
    raise(signum);
}

// ==========================================
// Exported C API
// ==========================================

int InitONNX() {
    // Register signal handler
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    
    return InferenceManager::Init();
}

int64_t CreateSession(const char* model_path) {
    return InferenceManager::CreateSession(model_path);
}

void ReleaseSession(int64_t session_id) {
    InferenceManager::ReleaseSession(session_id);
}

void Inference_Shutdown() {
    if (g_local_shutdown_requested.load()) {
        // Signal handler already requested shutdown, but we might be called by app too.
    }
    
    // Release all resources
    VideoManager::ReleaseAll();
    InferenceManager::Shutdown();
}

void Native_ForceExit() {
    std::cout << "[Native] Force Exit requested - calling _Exit(0)" << std::endl;
    std::cout.flush();
    std::cerr.flush();
    std::_Exit(0);
}

void Session_ClearInputs(int64_t session_id) {
    InferenceManager::ClearInputs(session_id);
}

void Session_AddInput(int64_t session_id, const char* name, float* data, int64_t* dims, int rank) {
    InferenceManager::AddInput(session_id, name, data, dims, rank);
}

int Session_Run(int64_t session_id, const char** output_names, int num_outputs) {
    return InferenceManager::Run(session_id, output_names, num_outputs);
}

int Session_GetOutput(int64_t session_id, int index, float** out_data, int64_t** out_dims, int* out_rank, int64_t* out_count) {
    return InferenceManager::GetOutput(session_id, index, out_data, out_dims, out_rank, out_count);
}

int Session_GetLabels(int64_t session_id, const char** out_labels, int* out_length) {
    return InferenceManager::GetLabels(session_id, out_labels, out_length);
}

// ==========================================
// Video Capture API
// ==========================================

int64_t Video_Open(const char* url) {
    return VideoManager::Open(url);
}

void Video_Release(int64_t video_id) {
    VideoManager::Release(video_id);
}

double Video_GetFPS(int64_t video_id) {
    return VideoManager::GetFPS(video_id);
}

int Video_GetFrame(int64_t video_id, uint8_t** out_buffer, int* width, int* height, int64_t* out_timestamp) {
    return VideoManager::GetFrame(video_id, out_buffer, width, height, out_timestamp);
}

int PreprocessImage(uint8_t* in_data, int width, int height, float* out_data) {
    return ImageProcessor::Preprocess(in_data, width, height, out_data);
}

// ==========================================
// Combined Loop (Capture + Infer)
// ==========================================

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
    // Get frame WITHOUT adding to texture buffer (we'll add after inference)
    int ret = VideoManager::GetFrame(video_id, out_frame_buffer, out_width, out_height, &timestamp, false);
    if (ret != 0) return ret; 
    
    if (out_timestamp) *out_timestamp = timestamp;

    // 2. Get Contexts
    auto video_ctx = VideoManager::GetContext(video_id);
    auto ctx = InferenceManager::GetContext(session_id);
    
    if (!ctx) return 10; // Session not found

    std::lock_guard<std::mutex> lock(ctx->mutex);
    
    // ========================================
    // GPU INFERENCE PATH (Full Zero-Copy)
    // ========================================
    #ifdef HAVE_OPENCV_CUDAIMGPROC
    if (video_ctx && video_ctx->has_gpu_frame && !video_ctx->last_rgba_gpu.empty()) {
        float* cuda_tensor_ptr = nullptr;
        
        if (ImageProcessor::PreprocessGpu(video_ctx->last_rgba_gpu, &cuda_tensor_ptr, ctx.get())) {
            try {
                Ort::MemoryInfo cuda_mem_info("Cuda", OrtDeviceAllocator, 0, OrtMemTypeDefault);
                int64_t input_dims[] = {1, 3, 640, 640};
                size_t tensor_size = 1 * 3 * 640 * 640;
                
                ctx->input_name_strings.clear();
                ctx->input_tensors.clear();
                ctx->input_name_strings.push_back(std::string(input_name));
                
                Ort::Value tensor = Ort::Value::CreateTensor<float>(
                    cuda_mem_info, 
                    cuda_tensor_ptr, 
                    tensor_size, 
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
                
                static int gpu_infer_count = 0;
                if (gpu_infer_count < 3) {
                    std::cout << "[GPU-INFER] ✓ Full GPU inference complete in " 
                              << duration.count() << "ms" << std::endl;
                    gpu_infer_count++;
                }
                
                // CRITICAL: Add frame to texture buffer AFTER successful inference
                if (video_ctx->texture_manager_id > 0 || video_ctx->texture_id > 0) {
                    int tex_id = video_ctx->texture_manager_id > 0 ? video_ctx->texture_manager_id : video_ctx->texture_id;
                    texture_manager::TextureManager::getInstance().setPendingGpuFrame(tex_id, video_ctx->last_rgba_gpu, timestamp);
                } else {
                    std::cerr << "[INFERENCE-BRIDGE] ERROR: No texture ID configured for frame " << timestamp << std::endl;
                }
                
                return 0;
                
            } catch (const std::exception& e) {
                std::cerr << "[GPU-INFER] CUDA tensor inference failed: " << e.what() 
                          << " - falling back to CPU" << std::endl;
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
    
    ret = ImageProcessor::Preprocess(*out_frame_buffer, *out_width, *out_height, ctx->preprocess_buffer.data());
    if (ret != 0) return 11;

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
                
        // CRITICAL: Add frame to texture buffer AFTER successful inference
        if (video_ctx->texture_manager_id > 0 || video_ctx->texture_id > 0) {
            int tex_id = video_ctx->texture_manager_id > 0 ? video_ctx->texture_manager_id : video_ctx->texture_id;
            texture_manager::TextureManager::getInstance().setPendingGpuFrame(tex_id, video_ctx->last_rgba_gpu, timestamp);
        } else {
            std::cerr << "[INFERENCE-BRIDGE] ERROR: No texture ID configured for frame " << timestamp << std::endl;
        }
                
        return 0;

    } catch (const std::exception& e) {
        std::cerr << "[Native] Loop Infer failed: " << e.what() << std::endl;
        return 12;
    }
}

int Video_InferenceOnly(
    int64_t video_id, 
    int64_t session_id, 
    const char* input_name,
    const char** output_names, 
    int num_outputs,
    float* out_inference_time
) {
    auto start_time = std::chrono::high_resolution_clock::now();

    // 1. Get Contexts
    auto video_ctx = VideoManager::GetContext(video_id);
    auto ctx = InferenceManager::GetContext(session_id);
    
    if (!ctx) return 10; // Session not found
    if (!video_ctx) return 13; // Video not found

    std::lock_guard<std::mutex> lock(ctx->mutex);
    
    // ========================================
    // GPU INFERENCE PATH (Full Zero-Copy)
    // ========================================
    #ifdef HAVE_OPENCV_CUDAIMGPROC
    if (video_ctx->has_gpu_frame && !video_ctx->last_rgba_gpu.empty()) {
        float* cuda_tensor_ptr = nullptr;
        
        if (ImageProcessor::PreprocessGpu(video_ctx->last_rgba_gpu, &cuda_tensor_ptr, ctx.get())) {
            try {
                Ort::MemoryInfo cuda_mem_info("Cuda", OrtDeviceAllocator, 0, OrtMemTypeDefault);
                int64_t input_dims[] = {1, 3, 640, 640};
                size_t tensor_size = 1 * 3 * 640 * 640;
                
                ctx->input_name_strings.clear();
                ctx->input_tensors.clear();
                ctx->input_name_strings.push_back(std::string(input_name));
                
                Ort::Value tensor = Ort::Value::CreateTensor<float>(
                    cuda_mem_info, 
                    cuda_tensor_ptr, 
                    tensor_size, 
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
                std::cerr << "[GPU-INFER] CUDA tensor inference failed: " << e.what() 
                          << " - falling back to CPU" << std::endl;
            }
        }
    }
    #endif
    
    // ========================================
    // CPU INFERENCE PATH (Fallback)
    // ========================================
    // Note: This assumes that the last_rgba_gpu frame exists and can be downloaded.
    // However, in our system, if we are in CPU mode, VideoManager::GetFrame would have 
    // already populated the CPU buffer.
    // For simplicity, if GPU path fails, we return error here because the CPU frame 
    // buffer management is different (it's passed out of GetFrame).
    
    return 14; // Inference only currently supported on GPU path
}

// ==========================================
// Texture Wrappers
// ==========================================

extern "C" {

#define TEXTURE_EXPORT __attribute__((visibility("default"))) __attribute__((used))

TEXTURE_EXPORT void Video_SetTextureManagerId(long long session_id, int texture_manager_id) {
    VideoManager::SetTextureManagerId(session_id, texture_manager_id);
}

TEXTURE_EXPORT int Texture_Create(int width, int height) {
    return texture_manager::TextureManager::getInstance().createTexture(width, height);
}

TEXTURE_EXPORT uint32_t Texture_GetGLHandle(int texture_id) {
    auto info = texture_manager::TextureManager::getInstance().getTexture(texture_id);
    return info ? info->gl_texture_id : 0;
}

TEXTURE_EXPORT int Texture_GetDimensions(int texture_id, int* width, int* height) {
    if (texture_manager::TextureManager::getInstance().getTextureDimensions(texture_id, width, height)) {
        return 0;
    }
    return -1;
}

TEXTURE_EXPORT int Texture_UploadPending(int texture_id) {
    if (texture_manager::TextureManager::getInstance().uploadPendingFrame(texture_id)) {
        return 0;
    }
    return -1;
}

TEXTURE_EXPORT int Texture_HasValidFrame(int texture_id) {
    return texture_manager::TextureManager::getInstance().hasValidFrame(texture_id) ? 1 : 0;
}

TEXTURE_EXPORT int Texture_EnsureGLTexture(int texture_id) {
    return texture_manager::TextureManager::getInstance().ensureGLTexture(texture_id) ? 0 : -1;
}

TEXTURE_EXPORT int Texture_ShowFrame(int texture_id, int64_t timestamp) {
    return texture_manager::TextureManager::getInstance().showFrame(texture_id, timestamp) ? 0 : -1;
}

TEXTURE_EXPORT void Texture_Dispose(int texture_id) {
    texture_manager::TextureManager::getInstance().releaseTexture(texture_id);
}

} // extern "C"
