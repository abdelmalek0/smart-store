#include "image_processor.h"
#include <iostream>
#include <vector>
#include <cstring>

#ifdef HAVE_OPENCV_CUDAIMGPROC
#include <opencv2/cudaimgproc.hpp>
#include <opencv2/cudawarping.hpp>
#include <opencv2/cudaarithm.hpp>
#endif

int ImageProcessor::Preprocess(uint8_t* in_data, int width, int height, float* out_data) {
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

#include "inference_manager.h"

bool ImageProcessor::PreprocessGpu(const cv::cuda::GpuMat& rgba_gpu, float** out_cuda_ptr, SessionContext* ctx) {
    try {
        #ifdef HAVE_OPENCV_CUDAIMGPROC
        if (!ctx) return false;

        // 1. Convert RGBA -> RGB on GPU
        cv::cuda::cvtColor(rgba_gpu, ctx->gpu_rgb, cv::COLOR_RGBA2RGB);
        
        // 2. Resize to 640x640 on GPU
        cv::cuda::resize(ctx->gpu_rgb, ctx->gpu_resized, cv::Size(640, 640), 0, 0, cv::INTER_LINEAR);
        
        // 3. Convert to float and normalize (1/255) on GPU
        ctx->gpu_resized.convertTo(ctx->gpu_float, CV_32FC3, 1.0/255.0);
        
        // 4. CHW Transpose (HWC -> Planar) ON GPU (Zero CPU Hops)
        if (ctx->gpu_channels.size() != 3) ctx->gpu_channels.resize(3);
        for (int i = 0; i < 3; ++i) {
            if (ctx->gpu_channels[i].rows != 640 || ctx->gpu_channels[i].cols != 640) {
                ctx->gpu_channels[i].create(640, 640, CV_32FC1);
            }
        }
        cv::cuda::split(ctx->gpu_float, ctx->gpu_channels);
        
        // Ensure destination buffer is allocated at 3 x (640*640)
        if (ctx->gpu_preprocess_buffer.rows != 3 || ctx->gpu_preprocess_buffer.cols != 640*640) {
            ctx->gpu_preprocess_buffer.create(3, 640*640, CV_32FC1);
        }
        
        // Copy each channel to its plane in the destination buffer
        for (int i = 0; i < 3; ++i) {
            ctx->gpu_channels[i].reshape(1, 1).copyTo(ctx->gpu_preprocess_buffer.row(i));
        }
        
        // Resulting memory is guaranteed contiguous in cv::Mat/GpuMat rows
        *out_cuda_ptr = reinterpret_cast<float*>(ctx->gpu_preprocess_buffer.data);
        
        static int gpu_prep_count = 0;
        if (gpu_prep_count < 3) {
            std::cout << "[GPU-PREPROCESS] ✓ Fully GPU-native preprocessing (No CPU hops)" << std::endl;
            gpu_prep_count++;
        }
        
        return true;
        #else
        return false;
        #endif
    } catch (const std::exception& e) {
        std::cerr << "[GPU-PREPROCESS] Failed: " << e.what() << std::endl;
        return false;
    }
}
