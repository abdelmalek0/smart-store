#pragma once

#include <cstdint>
#include <opencv2/opencv.hpp>
#include <opencv2/core/cuda.hpp>

struct SessionContext;
class ImageProcessor {
public:
    static int Preprocess(uint8_t* in_data, int width, int height, float* out_data);
    
    // Optimized GPU-to-GPU preprocessing
    static bool PreprocessGpu(const cv::cuda::GpuMat& rgba_gpu, float** out_cuda_ptr, SessionContext* ctx);
};
