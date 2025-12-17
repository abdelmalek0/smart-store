
#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Initialize Environment (Global)
int InitONNX();

// Create a session for a model. Returns generated session_id (>0) or 0 on failure.
int64_t CreateSession(const char* model_path);

// Release a specific session
void ReleaseSession(int64_t session_id);

// Clear previously set inputs for the session (preparation for new run)
void Session_ClearInputs(int64_t session_id);

// Add an input tensor for the next run
// dims: array of dimensions (int64_t)
// rank: number of dimensions
void Session_AddInput(int64_t session_id, const char* name, float* data, int64_t* dims, int rank);

// Run inference
// output_names: array of strings for requested outputs
// num_outputs: size of output_names array
// Returns: 0 on success
int Session_Run(int64_t session_id, const char** output_names, int num_outputs);

// Get output data after run
// index: which output (0 to num_outputs-1)
// out_data: pointer to data buffer (managed by C++)
// out_dims: pointer to dimensions array (managed by C++)
// out_rank: pointer to rank
// out_count: pointer to total element count
// Returns 0 on success
int Session_GetOutput(int64_t session_id, int index, float** out_data, int64_t** out_dims, int* out_rank, int64_t* out_count);

#ifdef __cplusplus
}
#endif
