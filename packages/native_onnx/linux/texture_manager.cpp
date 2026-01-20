#include "texture_manager.h"
#include <iostream>
#include <opencv2/core/opengl.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/imgcodecs.hpp>

namespace texture_manager {

TextureManager& TextureManager::getInstance() {
    static TextureManager instance;
    return instance;
}

TextureManager::TextureManager() {
    std::cout << "[TextureManager] Initializing with CUDA-GL interop support..." << std::endl;
}

TextureManager::~TextureManager() {
    std::lock_guard<std::mutex> lock(map_mutex_);
    for (auto& pair : textures_) {
        auto& info = pair.second;
        
        // Unregister CUDA interop
        if (info.interop_registered && info.cuda_resource) {
            cudaGraphicsUnregisterResource(info.cuda_resource);
        }
        
        if (info.gl_texture_id) {
            glDeleteTextures(1, &info.gl_texture_id);
        }
    }
}

bool TextureManager::initializeGL() {
    if (gl_initialized_) return true;
    
    std::cout << "[TextureManager] Initializing OpenGL context..." << std::endl;
    
    const GLubyte* version = glGetString(GL_VERSION);
    if (!version) {
        std::cerr << "[TextureManager] ERROR: No OpenGL context available!" << std::endl;
        return false;
    }
    
    std::cout << "[TextureManager] OpenGL Version: " << version << std::endl;
    
    gl_initialized_ = true;
    return true;
}

bool TextureManager::registerCudaInterop(TextureInfo* info) {
    if (info->interop_registered) return true;
    if (info->gl_texture_id == 0) return false;
    
    cudaError_t err = cudaGraphicsGLRegisterImage(
        &info->cuda_resource,
        info->gl_texture_id,
        GL_TEXTURE_2D,
        cudaGraphicsRegisterFlagsWriteDiscard
    );
    
    if (err != cudaSuccess) {
        std::cerr << "[TextureManager] CUDA-GL interop registration failed: " 
                  << cudaGetErrorString(err) << std::endl;
        return false;
    }
    
    info->interop_registered = true;
    std::cout << "[TextureManager] ✓ CUDA-GL interop registered for GL texture " 
              << info->gl_texture_id << std::endl;
    return true;
}

int TextureManager::createTexture(int width, int height) {
    if (!initializeGL()) {
        std::cerr << "[TextureManager] Failed to initialize GL" << std::endl;
        return -1;
    }
    
    std::lock_guard<std::mutex> lock(map_mutex_);
    
    int texture_id = next_texture_id_++;
    TextureInfo info;
    info.width = width;
    info.height = height;
    info.gl_width = width;
    info.gl_height = height;
    
    // Create OpenGL texture
    glGenTextures(1, &info.gl_texture_id);
    glBindTexture(GL_TEXTURE_2D, info.gl_texture_id);
    
    // Allocate storage with black pixels (prevent garbage display)
    std::vector<uint8_t> black_pixels(width * height * 4, 0); // Open to optimization if needed for large textures
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, black_pixels.data());
    
    // Set texture parameters
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    glBindTexture(GL_TEXTURE_2D, 0);
    
    textures_[texture_id] = std::move(info);
    
    std::cout << "[TextureManager] Created texture " << texture_id 
              << " (GL=" << textures_[texture_id].gl_texture_id 
              << ", " << width << "x" << height << ")" << std::endl;
    
    return texture_id;
}

TextureInfo* TextureManager::getTexture(int texture_id) {
    std::lock_guard<std::mutex> lock(map_mutex_);
    auto it = textures_.find(texture_id);
    if (it == textures_.end()) return nullptr;
    return &it->second;
}

// ========================================
// ZERO-COPY GPU PATH (New Implementation)
// ========================================

bool TextureManager::setPendingGpuFrame(int texture_id, const cv::cuda::GpuMat& rgba_gpu) {
    TextureInfo* info = getTexture(texture_id);
    if (!info) return false;
    
    // Thread-safe: store GPU frame reference for later upload
    std::lock_guard<std::mutex> lock(*info->frame_mutex);
    rgba_gpu.copyTo(info->pending_gpu_frame);
    info->has_pending_gpu_frame = true;
    
    return true;
}

bool TextureManager::uploadPendingGpuFrame(int texture_id) {
    TextureInfo* info = getTexture(texture_id);
    if (!info) return false;
    
    cv::cuda::GpuMat frame_to_upload;
    
    // Thread-safe: grab pending GPU frame with DEEP COPY
    {
        std::lock_guard<std::mutex> lock(*info->frame_mutex);
        if (!info->has_pending_gpu_frame) return false;
        info->pending_gpu_frame.copyTo(frame_to_upload);
        info->has_pending_gpu_frame = false;
    }
    
    if (frame_to_upload.empty()) return false;
    
    // 1. Try CUDA-GL interop if not seen before
    if (!info->interop_registered && !info->interop_attempted) {
        info->interop_attempted = true;
        if (!registerCudaInterop(info)) {
            // Only log this once per texture
            std::cout << "[TextureManager] Texture " << texture_id 
                      << ": CUDA-GL interop unavailable, using direct GL upload" << std::endl;
        }
    }
    
    // 2. PATH A: DIRECT GL UPLOAD (Fallback)
    if (!info->interop_registered) {
        cv::Mat cpu_frame;
        frame_to_upload.download(cpu_frame);
        
        // Scale to texture size (avoid GL resize)
        cv::Mat frame_to_use;
        if (cpu_frame.cols != info->gl_width || cpu_frame.rows != info->gl_height) {
            cv::resize(cpu_frame, frame_to_use, cv::Size(info->gl_width, info->gl_height));
        } else {
            frame_to_use = cpu_frame;
        }
        
        if (!frame_to_use.isContinuous()) {
            frame_to_use = frame_to_use.clone();
        }
        
        // Upload to GL
        glBindTexture(GL_TEXTURE_2D, info->gl_texture_id);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 
                     frame_to_use.cols, frame_to_use.rows, 0,
                     GL_RGBA, GL_UNSIGNED_BYTE, frame_to_use.data);
                     
        // Update dimensions logic
        info->width = frame_to_use.cols;
        info->height = frame_to_use.rows;
        
        glBindTexture(GL_TEXTURE_2D, 0);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
        
        return true;
    }
    
    // 3. PATH B: CUDA-GL INTEROP (Zero-Copy)
    
    // Resize GL texture if needed
    if (frame_to_upload.cols != info->gl_width || frame_to_upload.rows != info->gl_height) {
        cudaGraphicsUnregisterResource(info->cuda_resource);
        
        glBindTexture(GL_TEXTURE_2D, info->gl_texture_id);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, frame_to_upload.cols, frame_to_upload.rows,
                     0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
        glBindTexture(GL_TEXTURE_2D, 0);
        
        info->gl_width = frame_to_upload.cols;
        info->gl_height = frame_to_upload.rows;
        
        if (!registerCudaInterop(info)) {
            info->interop_registered = false; // Fallback next time
            return false;
        }
    }
    
    // Map & Copy
    cudaError_t err = cudaGraphicsMapResources(1, &info->cuda_resource, 0);
    if (err != cudaSuccess) return false;
    
    cudaArray_t cuda_array;
    err = cudaGraphicsSubResourceGetMappedArray(&cuda_array, info->cuda_resource, 0, 0);
    if (err == cudaSuccess) {
        cudaMemcpy2DToArray(
            cuda_array, 0, 0,
            frame_to_upload.data, frame_to_upload.step,
            frame_to_upload.cols * 4, frame_to_upload.rows,
            cudaMemcpyDeviceToDevice
        );
    }
    
    cudaGraphicsUnmapResources(1, &info->cuda_resource, 0);
    
    info->width = frame_to_upload.cols;
    info->height = frame_to_upload.rows;
    
    return true;
}

// ========================================
// LEGACY CPU PATH (Fallback)
// ========================================

bool TextureManager::updateTextureFromGpuMat(int texture_id, const cv::cuda::GpuMat& rgba_gpu) {
    // Use zero-copy path now
    return setPendingGpuFrame(texture_id, rgba_gpu);
}

bool TextureManager::setPendingFrame(int texture_id, const cv::Mat& rgba_frame) {
    TextureInfo* info = getTexture(texture_id);
    if (!info) return false;
    
    // Upload to GPU first, then use GPU path
    cv::cuda::GpuMat gpu_frame;
    gpu_frame.upload(rgba_frame);
    return setPendingGpuFrame(texture_id, gpu_frame);
}

bool TextureManager::uploadPendingFrame(int texture_id) {
    // Redirect to GPU path
    return uploadPendingGpuFrame(texture_id);
}

void TextureManager::releaseTexture(int texture_id) {
    std::lock_guard<std::mutex> lock(map_mutex_);
    auto it = textures_.find(texture_id);
    if (it == textures_.end()) return;
    
    auto& info = it->second;
    
    // Unregister CUDA interop first
    if (info.interop_registered && info.cuda_resource) {
        cudaGraphicsUnregisterResource(info.cuda_resource);
    }
    
    if (info.gl_texture_id) {
        glDeleteTextures(1, &info.gl_texture_id);
    }
    
    textures_.erase(it);
    std::cout << "[TextureManager] Released texture " << texture_id << std::endl;
}

GLuint TextureManager::getGLTextureId(int texture_id) {
    TextureInfo* info = getTexture(texture_id);
    return info ? info->gl_texture_id : 0;
}

bool TextureManager::getTextureDimensions(int texture_id, int* width, int* height) {
    TextureInfo* info = getTexture(texture_id);
    if (!info) return false;
    
    if (width) *width = info->width;
    if (height) *height = info->height;
    return true;
}

} // namespace texture_manager
