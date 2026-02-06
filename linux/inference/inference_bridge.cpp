
#include "inference_bridge.h"
#include <onnxruntime_cxx_api.h>
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
static std::mutex g_mutex;

int InitONNX() {
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
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_env) InitONNX();

    try {
        Ort::SessionOptions session_options;
        session_options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);

        // GPU Configuration - CUDA Only
        bool gpu_success = false;
        
        try {
            OrtCUDAProviderOptions cuda_options;
            cuda_options.device_id = 0;
            // Enable memory arena for better performance
            cuda_options.arena_extend_strategy = 0; // kNextPowerOfTwo
            cuda_options.gpu_mem_limit = SIZE_MAX; // No limit
            cuda_options.cudnn_conv_algo_search = OrtCudnnConvAlgoSearchDefault;
            
            session_options.AppendExecutionProvider_CUDA(cuda_options);
            gpu_success = true;
            std::cout << "[Native] ✓ Enabled CUDA for " << model_path << std::endl;
        } catch (const std::exception& e) {
            std::cerr << "[Native] CUDA initialization failed: " << e.what() << std::endl;
        } catch (...) {
            std::cerr << "[Native] CUDA initialization failed with unknown error" << std::endl;
        }
        
        if (!gpu_success) {
            std::cerr << "[Native] ⚠ Falling back to CPU for " << model_path << std::endl;
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

void ReleaseSession(int64_t session_id) {
    std::lock_guard<std::mutex> lock(g_mutex);
    g_contexts.erase(session_id);
    std::cout << "[Native] Session " << session_id << " released." << std::endl;
}

void Session_ClearInputs(int64_t session_id) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_contexts.find(session_id);
    if (it == g_contexts.end()) return;
    
    auto& ctx = it->second;
    ctx->input_name_strings.clear();
    ctx->input_tensors.clear();
}

void Session_AddInput(int64_t session_id, const char* name, float* data, int64_t* dims, int rank) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_contexts.find(session_id);
    if (it == g_contexts.end()) return;
    auto& ctx = it->second;

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
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_contexts.find(session_id);
    if (it == g_contexts.end()) return 1;
    auto& ctx = it->second;

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
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_contexts.find(session_id);
    if (it == g_contexts.end()) return 1;
    auto& ctx = it->second;
    
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

// Static storage for labels string (to keep memory valid after function returns)
static std::map<int64_t, std::string> g_labels_cache;

int Session_GetLabels(int64_t session_id, const char** out_labels, int* out_length) {
    std::lock_guard<std::mutex> lock(g_mutex);
    auto it = g_contexts.find(session_id);
    if (it == g_contexts.end()) {
        *out_labels = nullptr;
        *out_length = 0;
        return 1;
    }
    auto& ctx = it->second;

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

