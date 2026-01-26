#include "texture_manager.h"
#include <iostream>
#include <opencv2/core/opengl.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/imgcodecs.hpp>

// OpenGL extension functions for PBO (Pixel Buffer Objects)
// These may not be in the standard GL/gl.h
#define GL_PIXEL_UNPACK_BUFFER 0x88EC
#define GL_STREAM_DRAW 0x88E0

// Function pointers for OpenGL buffer operations
typedef void (*PFNGLGENBUFFERSPROC)(GLsizei n, GLuint* buffers);
typedef void (*PFNGLBINDBUFFERPROC)(GLenum target, GLuint buffer);
typedef void (*PFNGLBUFFERDATAPROC)(GLenum target, GLsizeiptr size, const void* data, GLenum usage);
typedef void (*PFNGLDELETEBUFFERSPROC)(GLsizei n, const GLuint* buffers);

// These will be loaded dynamically
static PFNGLGENBUFFERSPROC glGenBuffers_ptr = nullptr;
static PFNGLBINDBUFFERPROC glBindBuffer_ptr = nullptr;
static PFNGLBUFFERDATAPROC glBufferData_ptr = nullptr;
static PFNGLDELETEBUFFERSPROC glDeleteBuffers_ptr = nullptr;
static bool gl_funcs_loaded = false;

// Wrapper macros
#define glGenBuffers glGenBuffers_ptr
#define glBindBuffer glBindBuffer_ptr
#define glBufferData glBufferData_ptr
#define glDeleteBuffers glDeleteBuffers_ptr

// Load GL extension functions dynamically
#include <GL/glx.h>
static void loadGLFunctions() {
    if (gl_funcs_loaded) return;
    
    glGenBuffers_ptr = (PFNGLGENBUFFERSPROC)glXGetProcAddressARB((const GLubyte*)"glGenBuffers");
    glBindBuffer_ptr = (PFNGLBINDBUFFERPROC)glXGetProcAddressARB((const GLubyte*)"glBindBuffer");
    glBufferData_ptr = (PFNGLBUFFERDATAPROC)glXGetProcAddressARB((const GLubyte*)"glBufferData");
    glDeleteBuffers_ptr = (PFNGLDELETEBUFFERSPROC)glXGetProcAddressARB((const GLubyte*)"glDeleteBuffers");
    
    gl_funcs_loaded = true;
}

namespace texture_manager {

TextureManager& TextureManager::getInstance() {
    static TextureManager instance;
    return instance;
}

TextureManager::TextureManager() {}

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
    
    // Load OpenGL extension functions (PBO support)
    loadGLFunctions();
    
    // Initialize CUDA for GL interop
    // This must be done AFTER OpenGL context is current
    int cuda_device_count = 0;
    cudaError_t err = cudaGetDeviceCount(&cuda_device_count);
    if (err == cudaSuccess && cuda_device_count > 0) {
        // Get the CUDA device that corresponds to the current OpenGL context
        unsigned int gl_device_count = 0;
        int cuda_devices[8];
        err = cudaGLGetDevices(&gl_device_count, cuda_devices, 8, cudaGLDeviceListAll);
        
        if (err == cudaSuccess && gl_device_count > 0) {
            // Use the first CUDA device that matches OpenGL
            cudaSetDevice(cuda_devices[0]);
            std::cout << "[TextureManager] ✓ CUDA device " << cuda_devices[0] 
                      << " selected for GL interop" << std::endl;
        } else {
            // Fallback: just use device 0
            cudaSetDevice(0);
            std::cout << "[TextureManager] Using CUDA device 0 (GL device query failed: " 
                      << cudaGetErrorString(err) << ")" << std::endl;
        }
    } else {
        std::cerr << "[TextureManager] WARNING: No CUDA devices available for interop" << std::endl;
    }
    
    gl_initialized_ = true;
    return true;
}

bool TextureManager::registerCudaInterop(TextureInfo* info) {
    if (info->interop_registered) return true;
    if (info->gl_texture_id == 0) return false;
    
    // Make sure CUDA is initialized
    int device_count = 0;
    cudaError_t err = cudaGetDeviceCount(&device_count);
    if (err != cudaSuccess || device_count == 0) {
        std::cerr << "[TextureManager] CUDA not available: " << cudaGetErrorString(err) << std::endl;
        return false;
    }
    
    // Try multiple registration flag combinations for TEXTURE
    unsigned int flags[] = {
        cudaGraphicsRegisterFlagsWriteDiscard,
        cudaGraphicsRegisterFlagsSurfaceLoadStore,
        cudaGraphicsRegisterFlagsNone
    };
    const char* flag_names[] = {
        "WriteDiscard",
        "SurfaceLoadStore", 
        "None"
    };
    
    for (int i = 0; i < 3; i++) {
        err = cudaGraphicsGLRegisterImage(
            &info->cuda_resource,
            info->gl_texture_id,
            GL_TEXTURE_2D,
            flags[i]
        );
        
        if (err == cudaSuccess) {
            info->interop_registered = true;
            std::cout << "[TextureManager] ✓ CUDA-GL texture interop registered (flags=" 
                      << flag_names[i] << ") for GL texture " 
                      << info->gl_texture_id << std::endl;
            return true;
        }
        
        // Clear the error state
        cudaGetLastError();
    }
    
    std::cout << "[TextureManager] Texture interop failed, trying PBO path..." << std::endl;
    
    // ========================================
    // PBO FALLBACK: Create a Pixel Buffer Object and register that
    // PBO buffer interop often works when texture interop fails
    // ========================================
    
    // Create PBO for this texture
    int pbo_size = info->gl_width * info->gl_height * 4; // RGBA
    glGenBuffers(1, &info->pbo_id);
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, info->pbo_id);
    glBufferData(GL_PIXEL_UNPACK_BUFFER, pbo_size, nullptr, GL_STREAM_DRAW);
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
    
    GLenum gl_error = glGetError();
    if (gl_error != GL_NO_ERROR) {
        std::cerr << "[TextureManager] Failed to create PBO: GL error " << gl_error << std::endl;
        return false;
    }
    
    // Try to register PBO with CUDA
    err = cudaGraphicsGLRegisterBuffer(
        &info->pbo_cuda_resource,
        info->pbo_id,
        cudaGraphicsRegisterFlagsWriteDiscard
    );
    
    if (err == cudaSuccess) {
        info->pbo_registered = true;
        info->use_pbo_path = true;
        std::cout << "[TextureManager] ✓ CUDA-GL PBO interop registered for texture " 
                  << info->gl_texture_id << " (PBO=" << info->pbo_id << ")" << std::endl;
        return true;
    }
    
    std::cerr << "[TextureManager] PBO interop also failed: " << cudaGetErrorString(err) << std::endl;
    
    // Clean up PBO if registration failed
    glDeleteBuffers(1, &info->pbo_id);
    info->pbo_id = 0;
    
    std::cerr << "[TextureManager] All CUDA-GL interop registration attempts failed" << std::endl;
    return false;
}

int TextureManager::createTexture(int width, int height) {
    // NOTE: This may be called without a GL context!
    // We defer actual GL texture creation to ensureGLTexture()
    
    std::lock_guard<std::mutex> lock(map_mutex_);
    
    int texture_id = next_texture_id_++;
    TextureInfo info;
    info.width = width;
    info.height = height;
    info.gl_width = width;
    info.gl_height = height;
    info.gl_texture_id = 0;  // Deferred - will be created in ensureGLTexture
    
    textures_[texture_id] = std::move(info);
    
    std::cout << "[TextureManager] Reserved texture slot " << texture_id 
              << " (" << width << "x" << height << ") - GL creation deferred" << std::endl;
    
    return texture_id;
}

bool TextureManager::ensureGLTexture(int texture_id) {
    // MUST be called from UI thread with GL context!
    TextureInfo* info = getTexture(texture_id);
    if (!info) return false;
    
    // Already created?
    if (info->gl_texture_id != 0) return true;
    
    // Initialize GL if needed
    if (!initializeGL()) {
        std::cerr << "[TextureManager] Failed to initialize GL in ensureGLTexture" << std::endl;
        return false;
    }
    
    // Clear any previous GL errors
    while (glGetError() != GL_NO_ERROR) {}
    
    // Create OpenGL texture NOW (on correct GL context)
    glGenTextures(1, &info->gl_texture_id);
    glBindTexture(GL_TEXTURE_2D, info->gl_texture_id);
    
    // Allocate storage with black pixels
    std::vector<uint8_t> black_pixels(info->gl_width * info->gl_height * 4, 0);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, info->gl_width, info->gl_height, 0, 
                 GL_RGBA, GL_UNSIGNED_BYTE, black_pixels.data());
    
    GLenum gl_error = glGetError();
    if (gl_error != GL_NO_ERROR) {
        std::cerr << "[TextureManager] glTexImage2D error: " << gl_error << std::endl;
        info->gl_texture_id = 0;
        return false;
    }
    
    // Set texture parameters
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    glBindTexture(GL_TEXTURE_2D, 0);
    glFlush();  // Ensure texture is fully created
    
    std::cout << "[TextureManager] Created GL texture " << info->gl_texture_id 
              << " for slot " << texture_id << " (" << info->gl_width << "x" 
              << info->gl_height << ")" << std::endl;
    
    return true;
}

bool TextureManager::hasGLTexture(int texture_id) {
    TextureInfo* info = getTexture(texture_id);
    return info && info->gl_texture_id != 0;
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
    
    // 2. PATH A: PBO-based GPU transfer (when texture interop fails but PBO works)
    if (info->use_pbo_path && info->pbo_registered) {
        static bool pbo_logged = false;
        if (!pbo_logged) {
            std::cout << "[TextureManager] Using PBO path for GPU transfer" << std::endl;
            pbo_logged = true;
        }
        
        // Map PBO to CUDA
        cudaError_t err = cudaGraphicsMapResources(1, &info->pbo_cuda_resource, 0);
        if (err != cudaSuccess) {
            std::cerr << "[TextureManager] PBO map failed: " << cudaGetErrorString(err) << std::endl;
            goto cpu_fallback;
        }
        
        // Get device pointer to PBO
        void* pbo_ptr = nullptr;
        size_t pbo_size = 0;
        err = cudaGraphicsResourceGetMappedPointer(&pbo_ptr, &pbo_size, info->pbo_cuda_resource);
        if (err != cudaSuccess) {
            cudaGraphicsUnmapResources(1, &info->pbo_cuda_resource, 0);
            std::cerr << "[TextureManager] PBO get pointer failed: " << cudaGetErrorString(err) << std::endl;
            goto cpu_fallback;
        }
        
        // Copy from GPU frame to PBO (GPU-to-GPU transfer!)
        cudaMemcpy2D(pbo_ptr, frame_to_upload.cols * 4,
                     frame_to_upload.data, frame_to_upload.step,
                     frame_to_upload.cols * 4, frame_to_upload.rows,
                     cudaMemcpyDeviceToDevice);
        
        // Unmap PBO from CUDA
        cudaGraphicsUnmapResources(1, &info->pbo_cuda_resource, 0);
        
        // Now use OpenGL to copy from PBO to texture (GL-side operation, very fast)
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, info->pbo_id);
        glBindTexture(GL_TEXTURE_2D, info->gl_texture_id);
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 
                        frame_to_upload.cols, frame_to_upload.rows,
                        GL_RGBA, GL_UNSIGNED_BYTE, 0);  // 0 = read from bound PBO
        glBindTexture(GL_TEXTURE_2D, 0);
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
        
        info->width = frame_to_upload.cols;
        info->height = frame_to_upload.rows;
        info->has_valid_frame = true;
        
        return true;
    }
    
    // 3. PATH B: Direct CPU fallback (slowest - but always works)
cpu_fallback:
    {
        cv::Mat cpu_frame;
        frame_to_upload.download(cpu_frame);
        
        // Scale to texture size if needed
        cv::Mat frame_to_use;
        if (cpu_frame.cols != info->gl_width || cpu_frame.rows != info->gl_height) {
            cv::resize(cpu_frame, frame_to_use, cv::Size(info->gl_width, info->gl_height));
        } else {
            frame_to_use = cpu_frame;
        }
        
        if (!frame_to_use.isContinuous()) {
            frame_to_use = frame_to_use.clone();
        }
        
        // Upload to GL texture
        glBindTexture(GL_TEXTURE_2D, info->gl_texture_id);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        
        // Use glTexSubImage2D if texture already has correct size (faster)
        if (frame_to_use.cols == info->gl_width && frame_to_use.rows == info->gl_height) {
            glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0,
                            frame_to_use.cols, frame_to_use.rows,
                            GL_RGBA, GL_UNSIGNED_BYTE, frame_to_use.data);
        } else {
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 
                         frame_to_use.cols, frame_to_use.rows, 0,
                         GL_RGBA, GL_UNSIGNED_BYTE, frame_to_use.data);
            info->gl_width = frame_to_use.cols;
            info->gl_height = frame_to_use.rows;
        }
                     
        // Update dimensions
        info->width = frame_to_use.cols;
        info->height = frame_to_use.rows;
        
        glBindTexture(GL_TEXTURE_2D, 0);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
        
        // Ensure GL commands complete before Flutter samples
        glFlush();
        
        info->has_valid_frame = true;
        return true;
    }
    
    return false;  // Should not reach here
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

bool TextureManager::hasValidFrame(int texture_id) {
    TextureInfo* info = getTexture(texture_id);
    return info ? info->has_valid_frame : false;
}

bool TextureManager::getTextureDimensions(int texture_id, int* width, int* height) {
    TextureInfo* info = getTexture(texture_id);
    if (!info) return false;
    
    if (width) *width = info->width;
    if (height) *height = info->height;
    return true;
}

} // namespace texture_manager
