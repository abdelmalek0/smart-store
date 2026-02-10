#pragma once

#include <onnxruntime_cxx_api.h>
#include <opencv2/core/cuda.hpp>
#include <vector>
#include <string>
#include <memory>
#include <mutex>
#include <map>

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

class InferenceManager {
public:
    static int Init();
    static void Shutdown();
    
    static int64_t CreateSession(const char* model_path);
    static void ReleaseSession(int64_t session_id);
    static void ReleaseAll();
    
    static void ClearInputs(int64_t session_id);
    static void AddInput(int64_t session_id, const char* name, float* data, int64_t* dims, int rank);
    static int Run(int64_t session_id, const char** output_names, int num_outputs);
    static int GetOutput(int64_t session_id, int index, float** out_data, int64_t** out_dims, int* out_rank, int64_t* out_count);
    
    static int GetLabels(int64_t session_id, const char** out_labels, int* out_length);

    // Helper access
    static std::shared_ptr<SessionContext> GetContext(int64_t session_id);
};
