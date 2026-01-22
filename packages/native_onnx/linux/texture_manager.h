#pragma once

#include <GL/gl.h>
#include <opencv2/core.hpp>
#include <opencv2/core/cuda.hpp>
#include <opencv2/cudaimgproc.hpp>
#include <map>
#include <mutex>

// CUDA-GL interop
#include <cuda_runtime.h>
#include <cuda_gl_interop.h>

namespace texture_manager {

struct TextureInfo {
    GLuint gl_texture_id = 0;
    int width = 0;      // Current frame width
    int height = 0;     // Current frame height
    int gl_width = 0;   // Allocated GL texture width
    int gl_height = 0;  // Allocated GL texture height
    
    // CUDA-GL interop for zero-copy texture updates
    cudaGraphicsResource_t cuda_resource = nullptr;
    bool interop_registered = false;
    bool interop_attempted = false;  // Track if interop was already tried (to avoid repeated failures)
    
    // PBO (Pixel Buffer Object) for CUDA-GL buffer interop
    // This works when direct texture interop fails (e.g., on EGL contexts)
    GLuint pbo_id = 0;
    cudaGraphicsResource_t pbo_cuda_resource = nullptr;
    bool pbo_registered = false;
    bool use_pbo_path = false;  // Set to true if texture interop fails but PBO works
    
    // Frame readiness - prevents Flutter from sampling uninitialized texture
    bool has_valid_frame = false;  // Set to true after first successful frame upload
    
    // Pending GPU frame for deferred upload (thread-safe)
    cv::cuda::GpuMat pending_gpu_frame;
    bool has_pending_gpu_frame = false;
    std::unique_ptr<std::mutex> frame_mutex;
    
    TextureInfo() : frame_mutex(std::make_unique<std::mutex>()) {}
};

class TextureManager {
public:
    static TextureManager& getInstance();
    
    // Create a new texture for a video stream
    int createTexture(int width, int height);
    
    // Get texture info by ID
    TextureInfo* getTexture(int texture_id);
    
    // ZERO-COPY: Set pending GPU frame (called from capture thread - thread-safe)
    bool setPendingGpuFrame(int texture_id, const cv::cuda::GpuMat& rgba_gpu);
    
    // ZERO-COPY: Upload pending GPU frame to GL texture via CUDA interop
    // (called from UI thread with GL context)
    bool uploadPendingGpuFrame(int texture_id);
    
    // Legacy CPU methods (for fallback)
    bool updateTextureFromGpuMat(int texture_id, const cv::cuda::GpuMat& rgba_gpu);
    bool setPendingFrame(int texture_id, const cv::Mat& rgba_frame);
    bool uploadPendingFrame(int texture_id);
    
    // Release texture
    void releaseTexture(int texture_id);
    
    // Get OpenGL texture ID for Flutter
    GLuint getGLTextureId(int texture_id);
    
    // Check if texture has valid frame content (safe to sample)
    bool hasValidFrame(int texture_id);
    
    // Check if GL texture has been created (may be deferred)
    bool hasGLTexture(int texture_id);
    
    // Ensure GL texture is created (call from UI thread with GL context)
    bool ensureGLTexture(int texture_id);
    
    // Get texture dimensions (returns false if not found)
    bool getTextureDimensions(int texture_id, int* width, int* height);

private:
    TextureManager();
    ~TextureManager();
    
    // Initialize OpenGL context (called once)
    bool initializeGL();
    
    // Register GL texture with CUDA for interop
    bool registerCudaInterop(TextureInfo* info);
    
    std::map<int, TextureInfo> textures_;
    std::mutex map_mutex_;
    int next_texture_id_ = 1;
    bool gl_initialized_ = false;
};

} // namespace texture_manager

