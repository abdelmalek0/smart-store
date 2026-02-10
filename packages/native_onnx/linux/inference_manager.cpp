#include "inference_manager.h"
#include <iostream>
#include <mutex>
#include <map>
#include <vector>
#include <atomic>
#include <algorithm>

#ifdef USE_CUDA
#include <cuda_runtime.h>
#endif

// Global Environment
static std::unique_ptr<Ort::Env> g_env;
static std::unique_ptr<Ort::AllocatorWithDefaultOptions> g_allocator;
static std::mutex g_env_mutex;

// Session Management
static std::map<int64_t, std::shared_ptr<SessionContext>> g_contexts;
static int64_t g_next_session_id = 1;
static std::mutex g_contexts_mutex;

static std::atomic<bool> g_shutdown_called{false};

int InferenceManager::Init() {
    std::lock_guard<std::mutex> lock(g_env_mutex);
    g_shutdown_called.store(false);
    
    try {
        if (!g_env) {
            g_env = std::make_unique<Ort::Env>(ORT_LOGGING_LEVEL_WARNING, "NativeONNX");
            g_allocator = std::make_unique<Ort::AllocatorWithDefaultOptions>();
            
            std::cout << "[Native] ONNX Runtime initialized" << std::endl;
            
            // GPU Capability Check
            std::cout << "[GPU-CHECK] Verifying GPU capabilities..." << std::endl;
            
            #ifdef USE_CUDA
            int deviceCount = 0;
            cudaError_t err = cudaGetDeviceCount(&deviceCount);
            if (err == cudaSuccess && deviceCount > 0) {
                cudaDeviceProp prop;
                cudaGetDeviceProperties(&prop, 0);
                std::cout << "[GPU-CHECK] ✓ CUDA Device: " << prop.name 
                         << " (Compute " << prop.major << "." << prop.minor << ")" << std::endl;
                
                #ifdef CUDNN_MAJOR
                std::cout << "[GPU-CHECK] ✓ cuDNN version: " << CUDNN_MAJOR << "." << CUDNN_MINOR << std::endl;
                #endif
            } else {
                std::cout << "[GPU-CHECK] ⚠ CUDA not available or no devices found" << std::endl;
            }
            #else
            std::cout << "[GPU-CHECK] ⚠ ONNX Runtime not compiled with CUDA support" << std::endl;
            #endif
            
            #ifdef HAVE_OPENCV_CUDAIMGPROC
            std::cout << "[GPU-CHECK] ✓ OpenCV CUDA modules: ENABLED" << std::endl;
            #else
            std::cout << "[GPU-CHECK] ⚠ OpenCV CUDA modules: NOT AVAILABLE" << std::endl;
            #endif
            
            std::cout << "[GPU-CHECK] ========================================" << std::endl;
        }
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "[Native] Error initializing ONNX: " << e.what() << std::endl;
        return 1;
    }
}

int64_t InferenceManager::CreateSession(const char* model_path) {
    std::lock_guard<std::mutex> lock(g_contexts_mutex);
    if (!g_env) Init();

    try {
        Ort::SessionOptions session_options;
        session_options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
        session_options.SetLogSeverityLevel(3); 

        bool gpu_success = false;
        std::string provider_name = "";
        
        std::cout << "[Native] ========================================" << std::endl;
        std::cout << "[Native] Creating session for: " << model_path << std::endl;

        // Fallback to CUDA
        if (!gpu_success) {
            try {
                std::cout << "[Native] Attempting CUDA..." << std::endl;
                OrtCUDAProviderOptions cuda_options{};
                cuda_options.device_id = 0;
                cuda_options.arena_extend_strategy = 0; 
                cuda_options.gpu_mem_limit = SIZE_MAX; 
                cuda_options.cudnn_conv_algo_search = OrtCudnnConvAlgoSearchExhaustive; 
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
             return 0;
        } else {
             std::cout << "[Native] ✓ Enabled " << provider_name << " for " << model_path << std::endl;
        }
        
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

void InferenceManager::ReleaseSession(int64_t session_id) {
    std::lock_guard<std::mutex> lock(g_contexts_mutex);
    auto it = g_contexts.find(session_id);
    if (it != g_contexts.end()) {
        auto& ctx = it->second;
        // Release CUDA resources explicitly if needed
        if (ctx->cuda_tensor_ptr) {
#ifdef USE_CUDA
            cudaFree(ctx->cuda_tensor_ptr);
#endif
            ctx->cuda_tensor_ptr = nullptr;
        }
        ctx->gpu_preprocess_buffer.release();
        g_contexts.erase(it);
        std::cout << "[Native] Session " << session_id << " released." << std::endl;
    }
}

void InferenceManager::ReleaseAll() {
    std::lock_guard<std::mutex> lock(g_contexts_mutex);
    int session_count = g_contexts.size();
    for (auto& pair : g_contexts) {
        auto& ctx = pair.second;
        ctx->input_tensors.clear();
        ctx->output_tensors.clear();
        if (ctx->cuda_tensor_ptr) {
#ifdef USE_CUDA
            cudaFree(ctx->cuda_tensor_ptr);
#endif
            ctx->cuda_tensor_ptr = nullptr;
        }
        ctx->gpu_preprocess_buffer.release();
        ctx->session.reset();
    }
    g_contexts.clear();
    std::cout << "[Native] ✓ Released " << session_count << " ONNX sessions" << std::endl;
}

void InferenceManager::Shutdown() {
    bool expected = false;
    if (!g_shutdown_called.compare_exchange_strong(expected, true)) {
        return;
    }
    
    std::cout << "[Native] Shutdown: Releasing GPU resources..." << std::endl;
    
    // Sessions released via ReleaseAll called by caller if needed, 
    // or we can call it here. But Inference_Shutdown in bridge called both video and inference release.
    // Here we only handle inference.
    ReleaseAll();
    
    {
        std::lock_guard<std::mutex> lock(g_env_mutex);
        g_allocator.reset();
        g_env.reset();
        std::cout << "[Native] ✓ Destroyed global ONNX environment" << std::endl;
    }
    
#ifdef USE_CUDA
    cudaDeviceSynchronize();
    std::cout << "[Native] ✓ CUDA synchronized" << std::endl;
#endif
    
    std::cout << "[Native] Shutdown complete" << std::endl;
}

void InferenceManager::ClearInputs(int64_t session_id) {
    auto ctx = GetContext(session_id);
    if (!ctx) return;
    
    std::lock_guard<std::mutex> lock(ctx->mutex);
    ctx->input_name_strings.clear();
    ctx->input_tensors.clear();
}

void InferenceManager::AddInput(int64_t session_id, const char* name, float* data, int64_t* dims, int rank) {
    auto ctx = GetContext(session_id);
    if (!ctx) return;

    std::lock_guard<std::mutex> lock(ctx->mutex);
    try {
        Ort::MemoryInfo memory_info = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
        
        size_t size = 1;
        for(int i=0; i<rank; i++) size *= dims[i];
        
        Ort::Value tensor = Ort::Value::CreateTensor<float>(
            memory_info, data, size, dims, rank);
            
        ctx->input_name_strings.push_back(std::string(name));
        ctx->input_tensors.push_back(std::move(tensor));
        
    } catch (const std::exception& e) {
        std::cerr << "[Native] AddInput failed: " << e.what() << std::endl;
    }
}

int InferenceManager::Run(int64_t session_id, const char** output_names, int num_outputs) {
    auto ctx = GetContext(session_id);
    if (!ctx) return 1;

    std::lock_guard<std::mutex> lock(ctx->mutex);
    try {
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

int InferenceManager::GetOutput(int64_t session_id, int index, float** out_data, int64_t** out_dims, int* out_rank, int64_t* out_count) {
    auto ctx = GetContext(session_id);
    if (!ctx) return 1;
    
    std::lock_guard<std::mutex> lock(ctx->mutex);
    
    if (index < 0 || index >= ctx->output_tensors.size()) return 2;
    
    try {
        auto& tensor = ctx->output_tensors[index];
        *out_data = tensor.GetTensorMutableData<float>();
        
        auto type_info = tensor.GetTensorTypeAndShapeInfo();
        
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
static std::mutex g_labels_mutex;

int InferenceManager::GetLabels(int64_t session_id, const char** out_labels, int* out_length) {
    auto ctx = GetContext(session_id);
    if (!ctx) {
        *out_labels = nullptr;
        *out_length = 0;
        return 1;
    }

    std::lock_guard<std::mutex> lock(ctx->mutex);
    
    try {
        Ort::AllocatorWithDefaultOptions allocator;
        auto metadata = ctx->session->GetModelMetadata();
        
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
            std::cout << "[Native] No label metadata found in model" << std::endl;
            *out_labels = nullptr;
            *out_length = 0;
            return 0; 
        }
        
        std::lock_guard<std::mutex> labels_lock(g_labels_mutex);
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

std::shared_ptr<SessionContext> InferenceManager::GetContext(int64_t session_id) {
    std::lock_guard<std::mutex> lock(g_contexts_mutex);
    auto it = g_contexts.find(session_id);
    if (it != g_contexts.end()) return it->second;
    return nullptr;
}
