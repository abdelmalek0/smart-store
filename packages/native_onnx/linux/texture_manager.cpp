#include "texture_manager.h"
#include <iostream>
#include <opencv2/core/opengl.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/imgcodecs.hpp>
#include <opencv2/cudaimgproc.hpp>
#include <opencv2/cudawarping.hpp>

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
#include <EGL/egl.h>
#include <EGL/eglext.h>

// EGL extension function pointers (strictly for EGLImage mapping)
typedef EGLImageKHR (*PFNEGLCREATEIMAGEKHRPROC)(EGLDisplay dpy, EGLContext ctx, EGLenum target, EGLClientBuffer buffer, const EGLint *attrib_list);
typedef EGLBoolean (*PFNEGLDESTROYIMAGEKHRPROC)(EGLDisplay dpy, EGLImageKHR image);
static PFNEGLCREATEIMAGEKHRPROC eglCreateImageKHR_ptr = nullptr;
static PFNEGLDESTROYIMAGEKHRPROC eglDestroyImageKHR_ptr = nullptr;

static void loadGLFunctions() {
    if (gl_funcs_loaded) return;
    
    // Load OpenGL PBO functions (standard support)
    glGenBuffers_ptr = (PFNGLGENBUFFERSPROC)glXGetProcAddressARB((const GLubyte*)"glGenBuffers");
    glBindBuffer_ptr = (PFNGLBINDBUFFERPROC)glXGetProcAddressARB((const GLubyte*)"glBindBuffer");
    glBufferData_ptr = (PFNGLBUFFERDATAPROC)glXGetProcAddressARB((const GLubyte*)"glBufferData");
    glDeleteBuffers_ptr = (PFNGLDELETEBUFFERSPROC)glXGetProcAddressARB((const GLubyte*)"glDeleteBuffers");
    
    // Load EGL functions for native NVIDIA EGLImage interop
    eglCreateImageKHR_ptr = (PFNEGLCREATEIMAGEKHRPROC)eglGetProcAddress("eglCreateImageKHR");
    eglDestroyImageKHR_ptr = (PFNEGLDESTROYIMAGEKHRPROC)eglGetProcAddress("eglDestroyImageKHR");
    
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
    // ========================================
    // PATH 1: Standard CUDA-GL Interop (Preferred for Forced-NVIDIA Context)
    // ========================================
    // Since the user is forcing `__GLX_VENDOR_LIBRARY_NAME=nvidia`, standard GL interop
    // is usually the most stable and avoids EGL-specific mapping "unknown errors".
    
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

    std::cout << "[TextureManager] Attempting standard CUDA-GL interop path..." << std::endl;
    for (int i = 0; i < 3; i++) {
        err = cudaGraphicsGLRegisterImage(
            &info->cuda_resource,
            info->gl_texture_id,
            GL_TEXTURE_2D,
            flags[i]
        );
        
        if (err == cudaSuccess) {
            info->interop_registered = true;
            info->use_dma_buf = false; // Not strictly EGL/DMA-buf path
            std::cout << "[TextureManager] ✓ CUDA-GL texture interop registered (flags=" 
                      << flag_names[i] << ")" << std::endl;
            return true;
        }
        cudaGetLastError();
    }

    // ========================================
    // PATH 2: NVIDIA EGLImage Interop (Fallback for Wayland)
    // ========================================
    EGLDisplay egl_dpy = eglGetCurrentDisplay();
    EGLContext egl_ctx = eglGetCurrentContext();
    
    if (egl_dpy != EGL_NO_DISPLAY && egl_ctx != EGL_NO_CONTEXT && eglCreateImageKHR_ptr) {
        std::cout << "[TextureManager] Falling back to NVIDIA EGLImageKHR interop..." << std::endl;
        const EGLint attribs[] = { EGL_IMAGE_PRESERVED_KHR, EGL_TRUE, EGL_NONE };
        
        info->egl_image = eglCreateImageKHR_ptr(
            egl_dpy, 
            egl_ctx, 
            EGL_GL_TEXTURE_2D_KHR, 
            (EGLClientBuffer)(uintptr_t)info->gl_texture_id, 
            attribs
        );
        
        if (info->egl_image != EGL_NO_IMAGE_KHR) {
            err = cudaGraphicsEGLRegisterImage(
                &info->cuda_resource, 
                info->egl_image, 
                cudaGraphicsRegisterFlagsWriteDiscard
            );
            
            if (err == cudaSuccess) {
                info->interop_registered = true;
                info->use_dma_buf = true;
                std::cout << "[TextureManager] ✓ NVIDIA-EGL image interop registered" << std::endl;
                return true;
            } else {
                std::cerr << "[TextureManager] cudaGraphicsEGLRegisterImage failed: " << cudaGetErrorString(err) << std::endl;
                if (eglDestroyImageKHR_ptr) eglDestroyImageKHR_ptr(egl_dpy, info->egl_image);
                info->egl_image = nullptr;
            }
        }
    }
    
    std::cerr << "[TextureManager] All NVIDIA-Native interop attempts failed" << std::endl;
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

bool TextureManager::setPendingGpuFrame(int texture_id, const cv::cuda::GpuMat& rgba_gpu, int64_t timestamp) {
    TextureInfo* info = getTexture(texture_id);
    if (!info) return false;
    
    std::lock_guard<std::mutex> lock(*info->frame_mutex);
    
    // 1. Store in Frame Buffer (Strict Sync)
    // Deep copy to ensure validity - use clone() to allocate new memory
    cv::cuda::GpuMat buffer_copy = rgba_gpu.clone();
    info->frame_buffer[timestamp] = buffer_copy;
    

    // 2. Buffer Size Management
    // Limit buffer size (max 15 frames ~ 0.5 sec) to reduce GPU memory pressure
    if (info->frame_buffer.size() > 15) {
        // Remove oldest
        info->frame_buffer.erase(info->frame_buffer.begin());
    }
    
    // 2. Auto-Play Mode (During Warmup)
    // If showFrame hasn't been called yet, display immediately to avoid black screen
    if (info->auto_play) {
        rgba_gpu.copyTo(info->pending_gpu_frame);
        info->has_pending_gpu_frame = true;
    }
    
    return true;
}

bool TextureManager::showFrame(int texture_id, int64_t timestamp) {
    TextureInfo* info = getTexture(texture_id);
    if (!info) return false;
    
    std::lock_guard<std::mutex> lock(*info->frame_mutex);
    
    // Disable auto-play once strict sync requested
    info->auto_play = false;
    
    // Look for exact timestamp
    auto it = info->frame_buffer.find(timestamp);
    if (it != info->frame_buffer.end()) {
        // Found! Set as pending for upload
        info->pending_gpu_frame = it->second; // Move reference (ref-counted)
        info->has_pending_gpu_frame = true;
        
        // STRICT SYNC: When a frame is shown, discard everything OLDER than it.
        // This prevents the system from ever "jumping back" if sync is slightly behind wall-time.
        info->frame_buffer.erase(info->frame_buffer.begin(), ++it);
        
        return true;
    }
    
    // Frame not found - use CLOSEST available frame as fallback (UI/Inference jitter)
    if (!info->frame_buffer.empty()) {
        auto it_next = info->frame_buffer.lower_bound(timestamp);
        auto it_match = it_next;
        
        if (it_next == info->frame_buffer.end()) {
            it_match = std::prev(it_next);
        } else if (it_next != info->frame_buffer.begin()) {
            auto it_prev = std::prev(it_next);
            // Pick the one with smaller absolute difference
            if (std::abs(it_next->first - timestamp) > std::abs(it_prev->first - timestamp)) {
                it_match = it_prev;
            }
        }
        
        // Log fallback usage periodically
        static int fallback_count = 0;
        if (++fallback_count % 300 == 0) { // Reduced logging frequency
            std::cout << "[TextureManager] Sync Fallback: Using " << it_match->first 
                      << " for requested " << timestamp << " (Diff: " 
                      << (it_match->first - timestamp) << "ms)" << std::endl;
        }
        
        info->pending_gpu_frame = it_match->second; // Move reference
        info->has_pending_gpu_frame = true;
        
        // Discard everything OLDER than the frame we just matched (Strict Sync)
        info->frame_buffer.erase(info->frame_buffer.begin(), ++it_match);
        
        return true;
    }
    
    // No frames available at all - this is the real error
    static int fail_count = 0;
    if (++fail_count % 30 == 0) {
        std::cerr << "[TextureManager] ❌ ShowFrame FAILED: Requested " << timestamp 
                  << ", buffer is EMPTY" << std::endl;
    }

    return false;
}

bool TextureManager::uploadPendingGpuFrame(int texture_id) {
    TextureInfo* info = getTexture(texture_id);
    if (!info) return false;
    
    cv::cuda::GpuMat frame_to_upload;
    
    // Thread-safe: grab pending GPU frame with DEEP COPY
    {
        std::lock_guard<std::mutex> lock(*info->frame_mutex);
        if (!info->has_pending_gpu_frame) return false;
        frame_to_upload = info->pending_gpu_frame; // Copy reference (GpuMat is ref-counted)
        info->pending_gpu_frame = cv::cuda::GpuMat(); // Clear source
        info->has_pending_gpu_frame = false;
    }
    
    if (frame_to_upload.empty()) return false;
    
    // 1. Try CUDA-GL or EGL interop if not seen before
    if (!info->interop_registered && !info->interop_attempted) {
        info->interop_attempted = true;
        if (!registerCudaInterop(info)) {
            // Only log this once per texture
            std::cout << "[TextureManager] Texture " << texture_id 
                      << ": CUDA-GL/EGL interop unavailable, using fallback path" << std::endl;
        }
    }
    
    // 2. PATH A: Direct NVIDIA Texture Interop (True Zero-Copy)
    if (info->interop_registered && info->cuda_resource) {
        // DYNAMIC RESOLUTION ADAPTATION:
        // If the frame resolution changed (or was initially incorrect), we MUST 
        // re-allocate the GL texture and re-register the interop.
        if (frame_to_upload.cols != info->gl_width || frame_to_upload.rows != info->gl_height) {
            std::cout << "[TextureManager] Dynamic Resize: Frame (" << frame_to_upload.cols << "x" << frame_to_upload.rows 
                      << ") vs Texture (" << info->gl_width << "x" << info->gl_height 
                      << "). Re-allocating..." << std::endl;
            
            // 1. Clean up old resources (CRITICAL: Must unregister before deleting GL texture)
            cudaGraphicsUnregisterResource(info->cuda_resource);
            info->cuda_resource = nullptr;
            
            if (info->use_dma_buf && info->egl_image && eglDestroyImageKHR_ptr) {
                EGLDisplay egl_dpy = eglGetCurrentDisplay();
                if (egl_dpy != EGL_NO_DISPLAY) eglDestroyImageKHR_ptr(egl_dpy, info->egl_image);
                info->egl_image = nullptr;
            }
            
            // 2. Re-allocate GL Texture at the correct size
            glBindTexture(GL_TEXTURE_2D, info->gl_texture_id);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, frame_to_upload.cols, frame_to_upload.rows, 0, 
                         GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
            
            info->gl_width = frame_to_upload.cols;
            info->gl_height = frame_to_upload.rows;
            
            // 3. Re-register for the new size
            info->interop_registered = false;
            if (!registerCudaInterop(info)) {
                std::cerr << "[TextureManager] Failed to re-register interop after dynamic resize!" << std::endl;
                return false;
            }
        }

        cudaError_t err = cudaGraphicsMapResources(1, &info->cuda_resource, 0);
        if (err == cudaSuccess) {
            cudaArray_t texture_ptr;
            err = cudaGraphicsSubResourceGetMappedArray(&texture_ptr, info->cuda_resource, 0, 0);
            if (err == cudaSuccess) {
                // EXPLICIT HARDWARE COPY: Push NVIDIA GpuMat to NVIDIA Texture Array
                err = cudaMemcpy2DToArray(
                    texture_ptr, 0, 0, 
                    frame_to_upload.data, frame_to_upload.step,
                    frame_to_upload.cols * 4, frame_to_upload.rows, 
                    cudaMemcpyDeviceToDevice
                );
                
                if (err != cudaSuccess) {
                    std::cerr << "[TextureManager] cudaMemcpy2DToArray FAILED (" 
                              << frame_to_upload.cols << "x" << frame_to_upload.rows << " step=" << frame_to_upload.step 
                              << "): " << cudaGetErrorString(err) << std::endl;
                    cudaGraphicsUnmapResources(1, &info->cuda_resource, 0);
                    goto cpu_fallback_with_log;
                }
                
                // SYNCHRONIZATION: Ensure CUDA GPU write finished before GL samples it
                cudaGraphicsUnmapResources(1, &info->cuda_resource, 0);
                
                // GL SYNC: Flush GL command queue (lighter than glFinish)
                glFlush();
                
                info->width = frame_to_upload.cols;
                info->height = frame_to_upload.rows;
                info->has_valid_frame = true;
                
                // Log success occasionally
                static int success_count = 0;
                if (++success_count % 600 == 0) {
                    std::cout << "[TextureManager] ✓ Zero-Copy Push (" << frame_to_upload.cols << "x" << frame_to_upload.rows 
                              << ") successful" << std::endl;
                }
                return true;
            } else {
                std::cerr << "[TextureManager] cudaGraphicsSubResourceGetMappedArray failed: " << cudaGetErrorString(err) << std::endl;
                cudaGraphicsUnmapResources(1, &info->cuda_resource, 0);
            }
        } else {
            // Mapping failed - UNREGISTER and retry other path next frame
            std::cerr << "[TextureManager] cudaGraphicsMapResources failed: " << cudaGetErrorString(err) << std::endl;
            
            // Clean up to allow a fresh registration attempt
            cudaGraphicsUnregisterResource(info->cuda_resource);
            info->cuda_resource = nullptr;
            
            if (info->use_dma_buf && info->egl_image && eglDestroyImageKHR_ptr) {
                EGLDisplay egl_dpy = eglGetCurrentDisplay();
                if (egl_dpy != EGL_NO_DISPLAY) {
                    eglDestroyImageKHR_ptr(egl_dpy, info->egl_image);
                }
                info->egl_image = nullptr;
            }
            
            info->interop_registered = false;
            info->interop_attempted = false; // Allow retry in registerCudaInterop
        }
    }
    
    // 3. PATH B: CPU Fallback (Wait, why are we here? App is ON NVIDIA)
    // If we are here, something went wrong with the NVIDIA Interop.
    // Try slow path to at least see if pixels are valid.
cpu_fallback_with_log:
    {
        static bool fallback_warned = false;
        if (!fallback_warned) {
            std::cout << "[TextureManager] WARNING: Direct interop failed or not registered. Using slow fallback." << std::endl;
            fallback_warned = true;
        }
        
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
    // Timestamps not available in legacy path, pass 0 (will work in auto-play mode)
    return setPendingGpuFrame(texture_id, rgba_gpu, 0);
}

bool TextureManager::setPendingFrame(int texture_id, const cv::Mat& rgba_frame) {
    TextureInfo* info = getTexture(texture_id);
    if (!info) return false;
    
    // Upload to GPU first, then use GPU path
    cv::cuda::GpuMat gpu_frame;
    gpu_frame.upload(rgba_frame);
    return setPendingGpuFrame(texture_id, gpu_frame, 0);
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
        info.cuda_resource = nullptr;
    }
    
    if (info.use_dma_buf && info.egl_image && eglDestroyImageKHR_ptr) {
        EGLDisplay egl_dpy = eglGetCurrentDisplay();
        if (egl_dpy != EGL_NO_DISPLAY) {
            eglDestroyImageKHR_ptr(egl_dpy, info.egl_image);
        }
        info.egl_image = nullptr;
    }
    
    if (info.pbo_id) {
        if (info.pbo_registered && info.pbo_cuda_resource) {
            cudaGraphicsUnregisterResource(info.pbo_cuda_resource);
        }
        if (glDeleteBuffers_ptr) glDeleteBuffers_ptr(1, &info.pbo_id);
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
