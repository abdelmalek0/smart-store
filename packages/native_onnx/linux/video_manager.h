#pragma once

#include <string>
#include <vector>
#include <memory>
#include <mutex>
#include <map>
#include <atomic>
#include <chrono>

#ifdef USE_FFMPEG_NVDEC
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/hwcontext.h>
#include <libavutil/hwcontext_cuda.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
}
#endif

#include <opencv2/opencv.hpp>
#include <opencv2/core/cuda.hpp>

struct VideoContext {
    // Synchronization State
    std::chrono::time_point<std::chrono::steady_clock> start_time;
    bool first_frame_read = false;
    int64_t start_pts = 0;
    int64_t last_timestamp = 0;

#ifdef USE_FFMPEG_NVDEC
    // FFmpeg structures for hardware decoding
    AVFormatContext* format_ctx = nullptr;
    AVCodecContext* codec_ctx = nullptr;
    AVBufferRef* hw_device_ctx = nullptr;
    AVFrame* frame = nullptr;
    AVFrame* sw_frame = nullptr;  // For transferring from GPU to CPU
    AVPacket* packet = nullptr;
    struct SwsContext* sws_ctx = nullptr;
    
    int video_stream_idx = -1;
    
    // Output buffer
    std::vector<uint8_t> rgba_buffer;
    int width = 0;
    int height = 0;
    
    // Cache to prevent swscale thrashing
    int last_width = 0;
    int last_height = 0;
    int last_format = -1;
    
    std::mutex mutex;  // Per-video mutex for thread safety
    
    // GPU Texture rendering (NEW)
    int texture_id = 0;  // TextureManager ID
    int texture_manager_id = 0;  // ID from Dart (for updates)
    bool use_gpu_texture = false;
    
    // GPU frame for zero-copy inference pipeline
    cv::cuda::GpuMat last_rgba_gpu;  // Store last RGBA frame on GPU
    bool has_gpu_frame = false;       // Flag indicating GPU frame is available
    
    // Per-stream NV12 conversion buffer (thread-safe alternative to static)
    std::vector<uint8_t> nv12_buffer;
#else
    // Fallback to OpenCV if FFmpeg not available
    std::unique_ptr<cv::VideoCapture> cap;
    std::mutex mutex;
    cv::Mat last_frame;
    std::vector<uint8_t> rgb_buffer;
#endif
};

class VideoManager {
public:
    static int64_t Open(const char* url);
    static void Release(int64_t video_id);
    static int GetFrame(int64_t video_id, uint8_t** out_buffer, int* width, int* height, int64_t* out_timestamp, bool add_to_texture_buffer = true);
    
    // Helper to access context securely for inference bridge internal use
    static std::shared_ptr<VideoContext> GetContext(int64_t video_id);
    
    static void SetTextureManagerId(int64_t video_id, int texture_manager_id);
    
    static void ReleaseAll();
};
