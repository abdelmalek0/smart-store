
#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifdef FLUTTER_PLUGIN_IMPL
#define ONNX_BRIDGE_EXPORT __attribute__((visibility("default")))
#else
#define ONNX_BRIDGE_EXPORT
#endif

// Initialize Environment (Global)
ONNX_BRIDGE_EXPORT int InitONNX();

// Create a session for a model. Returns generated session_id (>0) or 0 on failure.
ONNX_BRIDGE_EXPORT int64_t CreateSession(const char* model_path);

// Release a specific session
ONNX_BRIDGE_EXPORT void ReleaseSession(int64_t session_id);

// Shutdown all GPU resources - MUST be called before app exit!
// This prevents CUDA driver shutdown crashes.
ONNX_BRIDGE_EXPORT void Inference_Shutdown();

// Force immediate exit (bypasses static destructors)
ONNX_BRIDGE_EXPORT void Native_ForceExit();

// Clear previously set inputs for the session (preparation for new run)
ONNX_BRIDGE_EXPORT void Session_ClearInputs(int64_t session_id);

// Add an input tensor for the next run
// dims: array of dimensions (int64_t)
// rank: number of dimensions
ONNX_BRIDGE_EXPORT void Session_AddInput(int64_t session_id, const char* name, float* data, int64_t* dims, int rank);

// Run inference
// output_names: array of strings for requested outputs
// num_outputs: size of output_names array
// Returns: 0 on success
ONNX_BRIDGE_EXPORT int Session_Run(int64_t session_id, const char** output_names, int num_outputs);

// Get output data after run
// index: which output (0 to num_outputs-1)
// out_data: pointer to data buffer (managed by C++)
// out_dims: pointer to dimensions array (managed by C++)
// out_rank: pointer to rank
// out_count: pointer to total element count
// Returns 0 on success
ONNX_BRIDGE_EXPORT int Session_GetOutput(int64_t session_id, int index, float** out_data, int64_t** out_dims, int* out_rank, int64_t* out_count);

// ==========================================
// Video Capture API
// ==========================================

// Open a video stream (RTSP or File). Returns video_id > 0, or 0 on failure.
ONNX_BRIDGE_EXPORT int64_t Video_Open(const char* url);

// Release video resources
ONNX_BRIDGE_EXPORT void Video_Release(int64_t video_id);

// Get the next frame.
// out_buffer: pointer to pixel data (RGBA)
// width, height: output dimensions
// Returns 0 on success
ONNX_BRIDGE_EXPORT int Video_GetFrame(int64_t video_id, uint8_t** out_buffer, int* width, int* height, int64_t* out_timestamp);

// Get the next frame AND run inference on it (Zero-Copy optimization)
// input_name: name of input node (e.g. "images")
// Returns 0 on success
ONNX_BRIDGE_EXPORT int Video_GetFrameAndInfer(
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
);

// Preprocess an image (resize, normalize, HWC->CHW)
// in_data: RGBA pixel data
// out_data: Float buffer for ONNX input (1x3x640x640)
// Returns 0 on success
ONNX_BRIDGE_EXPORT int PreprocessImage(uint8_t* in_data, int width, int height, float* out_data);

// Get class labels from ONNX model metadata
// out_labels: pointer to C string containing the labels (typically a Python dict format)
// out_length: length of the labels string
// Returns 0 on success, labels may be empty if model has no label metadata
ONNX_BRIDGE_EXPORT int Session_GetLabels(int64_t session_id, const char** out_labels, int* out_length);

#ifdef __cplusplus
}
#endif

