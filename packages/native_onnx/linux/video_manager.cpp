#include "video_manager.h"
#include "texture_manager.h"
#include <iostream>
#include <map>
#include <thread>

#ifdef USE_NPP
#include <nppi_color_conversion.h>
#include <npp.h>
#endif

// Global storage for VideoContexts
static std::map<int64_t, std::shared_ptr<VideoContext>> g_video_contexts;
static int64_t g_next_video_id = 1;
static std::mutex g_video_mutex;

std::shared_ptr<VideoContext> VideoManager::GetContext(int64_t video_id) {
    std::lock_guard<std::mutex> lock(g_video_mutex);
    auto it = g_video_contexts.find(video_id);
    if (it != g_video_contexts.end()) {
        return it->second;
    }
    return nullptr;
}

int64_t VideoManager::Open(const char* url) {
    std::cout << "[NVDEC] ========================================" << std::endl;
    std::cout << "[NVDEC] Opening video: " << url << std::endl;
    
    std::lock_guard<std::mutex> lock(g_video_mutex);
    
    try {
#ifdef USE_FFMPEG_NVDEC
        auto ctx = std::make_shared<VideoContext>();
        
        // 1. Allocate format context
        ctx->format_ctx = avformat_alloc_context();
        
        // 2. Configure RTSP-specific options for reliable streaming
        AVDictionary* options = nullptr;
        std::string url_str(url);
        
        if (url_str.find("rtsp://") == 0) {
            std::cout << "[NVDEC] RTSP stream detected, configuring for reliability..." << std::endl;
            
            // Use TCP instead of UDP to avoid packet loss/distortion
            av_dict_set(&options, "rtsp_transport", "tcp", 0);
            
            // Set buffer size to handle network jitter
            av_dict_set(&options, "buffer_size", "4096000", 0);  // 4MB buffer
            
            // Reduce latency
            av_dict_set(&options, "max_delay", "500000", 0);  // 0.5 seconds
            
            // Allow discarding corrupted frames
            av_dict_set(&options, "fflags", "discardcorrupt", 0);
            
            // Set timeout
            av_dict_set(&options, "stimeout", "5000000", 0);  // 5 seconds
            
            // For low-latency streaming, don't analyze too long
            av_dict_set(&options, "analyzeduration", "500000", 0);  // 0.5s
            av_dict_set(&options, "probesize", "500000", 0);  // 500KB
        }
        
        // 3. Open input stream
        if (avformat_open_input(&ctx->format_ctx, url, nullptr, &options) < 0) {
            std::cerr << "[NVDEC] ❌ Failed to open input: " << url << std::endl;
            if (options) av_dict_free(&options);
            return 0;
        }
        
        if (options) av_dict_free(&options);
        
        // 2. Retrieve stream information
        if (avformat_find_stream_info(ctx->format_ctx, nullptr) < 0) {
            std::cerr << "[NVDEC] ❌ Failed to find stream info" << std::endl;
            avformat_close_input(&ctx->format_ctx);
            return 0;
        }
        
        // 3. Find video stream
        ctx->video_stream_idx = -1;
        for (unsigned int i = 0; i < ctx->format_ctx->nb_streams; i++) {
            if (ctx->format_ctx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
                ctx->video_stream_idx = i;
                break;
            }
        }
        
        if (ctx->video_stream_idx == -1) {
            std::cerr << "[NVDEC] ❌ No video stream found" << std::endl;
            avformat_close_input(&ctx->format_ctx);
            return 0;
        }
        
        AVCodecParameters* codecpar = ctx->format_ctx->streams[ctx->video_stream_idx]->codecpar;
        
        // 4. Determine correct NVDEC decoder
        const char* decoder_name = nullptr;
        switch (codecpar->codec_id) {
            case AV_CODEC_ID_H264: decoder_name = "h264_cuvid"; break;
            case AV_CODEC_ID_HEVC: decoder_name = "hevc_cuvid"; break;
            case AV_CODEC_ID_VP9:  decoder_name = "vp9_cuvid"; break;
            case AV_CODEC_ID_AV1:  decoder_name = "av1_cuvid"; break;
            default:
                std::cerr << "[NVDEC] ❌ Unsupported codec ID: " << codecpar->codec_id << std::endl;
                avformat_close_input(&ctx->format_ctx);
                return 0;
        }
        
        // 5. Find decoder
        const AVCodec* decoder = avcodec_find_decoder_by_name(decoder_name);
        if (!decoder) {
            std::cerr << "[NVDEC] ❌ Decoder " << decoder_name << " not found!" << std::endl;
            avformat_close_input(&ctx->format_ctx);
            return 0;
        }
        
        // 6. Create codec context
        ctx->codec_ctx = avcodec_alloc_context3(decoder);
        if (!ctx->codec_ctx) {
            avformat_close_input(&ctx->format_ctx);
            return 0;
        }
        
        if (avcodec_parameters_to_context(ctx->codec_ctx, codecpar) < 0) {
            avcodec_free_context(&ctx->codec_ctx);
            avformat_close_input(&ctx->format_ctx);
            return 0;
        }
        
        // 7. Create CUDA hardware device context
        if (av_hwdevice_ctx_create(&ctx->hw_device_ctx, AV_HWDEVICE_TYPE_CUDA, nullptr, nullptr, 0) < 0) {
            std::cerr << "[NVDEC] ❌ Failed to create CUDA device context" << std::endl;
            avcodec_free_context(&ctx->codec_ctx);
            avformat_close_input(&ctx->format_ctx);
            return 0;
        }
        
        ctx->codec_ctx->hw_device_ctx = av_buffer_ref(ctx->hw_device_ctx);
        
        // 9. Open codec
        if (avcodec_open2(ctx->codec_ctx, decoder, nullptr) < 0) {
            std::cerr << "[NVDEC] ❌ Failed to open decoder" << std::endl;
            av_buffer_unref(&ctx->hw_device_ctx);
            avcodec_free_context(&ctx->codec_ctx);
            avformat_close_input(&ctx->format_ctx);
            return 0;
        }
        
        // 10. Allocate frames
        ctx->frame = av_frame_alloc();
        ctx->sw_frame = av_frame_alloc();
        ctx->packet = av_packet_alloc();
        
        if (!ctx->frame || !ctx->sw_frame || !ctx->packet) {
            if (ctx->frame) av_frame_free(&ctx->frame);
            if (ctx->sw_frame) av_frame_free(&ctx->sw_frame);
            if (ctx->packet) av_packet_free(&ctx->packet);
            av_buffer_unref(&ctx->hw_device_ctx);
            avcodec_free_context(&ctx->codec_ctx);
            avformat_close_input(&ctx->format_ctx);
            return 0;
        }
        
        ctx->width = ctx->codec_ctx->width;
        ctx->height = ctx->codec_ctx->height;
        ctx->texture_id = 0;
        ctx->use_gpu_texture = true;
        
        int64_t id = g_next_video_id++;
        g_video_contexts[id] = ctx;
        
        std::cout << "[NVDEC] ✓ Hardware decoder initialized successfully. ID: " << id << std::endl;
        return id;
        
#else
        std::cout << "[VIDEO] ⚠ FFmpeg NVDEC not compiled, using OpenCV fallback" << std::endl;
        
        setenv("OPENCV_FFMPEG_CAPTURE_OPTIONS", "hwaccel;auto", 0);
        auto cap = std::make_unique<cv::VideoCapture>(url, cv::CAP_FFMPEG);
        
        if (!cap->isOpened()) {
            std::cerr << "[VIDEO] ❌ Failed to open video" << std::endl;
            return 0;
        }
        
        auto ctx = std::make_shared<VideoContext>();
        ctx->cap = std::move(cap);
        
        int64_t id = g_next_video_id++;
        g_video_contexts[id] = ctx;
        return id;
#endif
    } catch (const std::exception& e) {
        std::cerr << "[NVDEC] ❌ Exception: " << e.what() << std::endl;
        return 0;
    }
}

void VideoManager::Release(int64_t video_id) {
    std::lock_guard<std::mutex> lock(g_video_mutex);
    
#ifdef USE_FFMPEG_NVDEC
    auto it = g_video_contexts.find(video_id);
    if (it != g_video_contexts.end()) {
        auto& ctx = it->second;
        
        if (ctx->sws_ctx) sws_freeContext(ctx->sws_ctx);
        if (ctx->packet) av_packet_free(&ctx->packet);
        if (ctx->frame) av_frame_free(&ctx->frame);
        if (ctx->sw_frame) av_frame_free(&ctx->sw_frame);
        if (ctx->codec_ctx) avcodec_free_context(&ctx->codec_ctx);
        if (ctx->hw_device_ctx) av_buffer_unref(&ctx->hw_device_ctx);
        if (ctx->format_ctx) avformat_close_input(&ctx->format_ctx);
        
        // Clear GPU mats
        ctx->last_rgba_gpu.release();
        
        std::cout << "[NVDEC] Released video ID: " << video_id << std::endl;
    }
#endif
    
    g_video_contexts.erase(video_id);
}

void VideoManager::ReleaseAll() {
    std::lock_guard<std::mutex> lock(g_video_mutex);
    int video_count = g_video_contexts.size();
    
    for (auto& pair : g_video_contexts) {
        auto& ctx = pair.second;
#ifdef USE_FFMPEG_NVDEC
        if (ctx->sws_ctx) sws_freeContext(ctx->sws_ctx);
        if (ctx->packet) av_packet_free(&ctx->packet);
        if (ctx->frame) av_frame_free(&ctx->frame);
        if (ctx->sw_frame) av_frame_free(&ctx->sw_frame);
        if (ctx->codec_ctx) avcodec_free_context(&ctx->codec_ctx);
        if (ctx->hw_device_ctx) av_buffer_unref(&ctx->hw_device_ctx);
        if (ctx->format_ctx) avformat_close_input(&ctx->format_ctx);
        ctx->last_rgba_gpu.release();
#endif
    }
    g_video_contexts.clear();
    std::cout << "[Native] ✓ Released " << video_count << " video contexts" << std::endl;
}

void VideoManager::SetTextureManagerId(int64_t video_id, int texture_manager_id) {
    auto ctx = GetContext(video_id);
    if (ctx) {
        std::lock_guard<std::mutex> lock(ctx->mutex);
        ctx->texture_manager_id = texture_manager_id;
        ctx->use_gpu_texture = true;
        std::cout << "[BRIDGE] Linked video " << video_id << " to texture manager " << texture_manager_id << std::endl;
    }
}

int VideoManager::GetFrame(int64_t video_id, uint8_t** out_buffer, int* width, int* height, int64_t* out_timestamp) {
    std::shared_ptr<VideoContext> ctx;
    
    {
        std::lock_guard<std::mutex> lock(g_video_mutex);
        auto it = g_video_contexts.find(video_id);
        if (it == g_video_contexts.end()) return 1; 
        ctx = it->second;
    }
    
    std::lock_guard<std::mutex> lock(ctx->mutex);
    int64_t timestamp = 0;

#ifdef USE_FFMPEG_NVDEC
    static std::map<int64_t, int> frame_counts;
    
    while (true) {
        int ret = av_read_frame(ctx->format_ctx, ctx->packet);
        
        if (ret == AVERROR_EOF) {
            if (ctx->format_ctx->pb && ctx->format_ctx->pb->seekable) {
                av_seek_frame(ctx->format_ctx, ctx->video_stream_idx, 0, AVSEEK_FLAG_BACKWARD);
                avcodec_flush_buffers(ctx->codec_ctx);
                ctx->first_frame_read = false; 
                continue;
            } else {
                return 2;
            }
        }
        
        if (ret < 0) {
            if (ctx->format_ctx->pb && !ctx->format_ctx->pb->seekable) continue;
            return 2;
        }
        
        if (ctx->packet->stream_index != ctx->video_stream_idx) {
            av_packet_unref(ctx->packet);
            continue;
        }
        
        ret = avcodec_send_packet(ctx->codec_ctx, ctx->packet);
        av_packet_unref(ctx->packet);
        if (ret < 0) continue;
        
        ret = avcodec_receive_frame(ctx->codec_ctx, ctx->frame);
        if (ret == AVERROR(EAGAIN)) continue;
        else if (ret < 0) continue;
        
        // Timestamp logic
        if (ctx->frame->pts != AV_NOPTS_VALUE) {
            if (ctx->format_ctx->streams[ctx->video_stream_idx]->time_base.den > 0) {
                 timestamp = (int64_t)(ctx->frame->pts * av_q2d(ctx->format_ctx->streams[ctx->video_stream_idx]->time_base) * 1000);
            } else {
                 timestamp = ctx->frame->pts;
            }
        } else {
            timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::system_clock::now().time_since_epoch()
            ).count();
        }

        if (!ctx->first_frame_read) {
            ctx->start_time = std::chrono::steady_clock::now();
            ctx->start_pts = timestamp;
            ctx->first_frame_read = true;
        } else {
            auto now = std::chrono::steady_clock::now();
            auto elapsed_wall_ms = std::chrono::duration_cast<std::chrono::milliseconds>(now - ctx->start_time).count();
            auto elapsed_video_ms = timestamp - ctx->start_pts;
            
            if (elapsed_video_ms < (elapsed_wall_ms - 50)) {
                 av_frame_unref(ctx->frame);
                 continue; 
            }
        }
        break;
    }
    
    frame_counts[video_id]++;
    if (out_timestamp) *out_timestamp = timestamp;

    if (ctx->use_gpu_texture && (ctx->texture_id > 0 || ctx->texture_manager_id > 0)) {
        int src_width = ctx->frame->width;
        int src_height = ctx->frame->height;
        
        try {
            cv::cuda::GpuMat rgba_gpu;
            
#ifdef USE_NPP
             // ... NPP implementation ...
             if (ctx->frame->format == AV_PIX_FMT_CUDA) {
                int frame_w = ctx->frame->width;
                int frame_h = ctx->frame->height;
                
                cv::cuda::GpuMat rgb_gpu(frame_h, frame_w, CV_8UC3);
                rgba_gpu.create(frame_h, frame_w, CV_8UC4);
                
                const Npp8u* pSrc[2] = { (const Npp8u*)ctx->frame->data[0], (const Npp8u*)ctx->frame->data[1] };
                int nSrcStep = ctx->frame->linesize[0];
                NppiSize oSizeROI = {frame_w, frame_h};
                
                if (nppiNV12ToRGB_8u_P2C3R(pSrc, nSrcStep, rgb_gpu.ptr<Npp8u>(), (int)rgb_gpu.step, oSizeROI) == NPP_SUCCESS) {
                    cv::cuda::cvtColor(rgb_gpu, rgba_gpu, cv::COLOR_RGB2RGBA);
                    goto npp_done;
                }
            }
#endif
            {
                AVFrame* frame_to_convert = nullptr;
                if (ctx->frame->format == AV_PIX_FMT_CUDA) {
                    if (av_hwframe_transfer_data(ctx->sw_frame, ctx->frame, 0) < 0) {
                         av_frame_unref(ctx->frame);
                         return 2;
                    }
                    frame_to_convert = ctx->sw_frame;
                } else {
                    frame_to_convert = ctx->frame;
                }
                
                int frame_w = frame_to_convert->width;
                int frame_h = frame_to_convert->height;
                int uv_height = frame_h / 2;
                int nv12_size = frame_w * (frame_h + uv_height);
                
                if (ctx->nv12_buffer.size() != nv12_size) ctx->nv12_buffer.resize(nv12_size);
                
                int y_stride = frame_to_convert->linesize[0];
                int uv_stride = frame_to_convert->linesize[1];
                
                // Copy Y
                if (y_stride == frame_w) {
                    memcpy(ctx->nv12_buffer.data(), frame_to_convert->data[0], frame_w * frame_h);
                } else {
                    for(int i=0; i<frame_h; ++i) 
                        memcpy(ctx->nv12_buffer.data() + i*frame_w, frame_to_convert->data[0] + i*y_stride, frame_w);
                }
                
                // Copy UV
                uint8_t* uv_dest = ctx->nv12_buffer.data() + frame_w * frame_h;
                if (uv_stride == frame_w) {
                    memcpy(uv_dest, frame_to_convert->data[1], frame_w * uv_height);
                } else {
                    for(int i=0; i<uv_height; ++i)
                         memcpy(uv_dest + i*frame_w, frame_to_convert->data[1] + i*uv_stride, frame_w);
                }

                cv::Mat nv12_cpu(frame_h + uv_height, frame_w, CV_8UC1, ctx->nv12_buffer.data());
                cv::Mat rgba_cpu;
                cv::cvtColor(nv12_cpu, rgba_cpu, cv::COLOR_YUV2RGBA_NV12);
                rgba_gpu.upload(rgba_cpu);
            }

#ifdef USE_NPP
npp_done:
#endif
            int tex_id = ctx->texture_manager_id > 0 ? ctx->texture_manager_id : ctx->texture_id;
            texture_manager::TextureManager::getInstance().setPendingGpuFrame(tex_id, rgba_gpu, timestamp);
            
            ctx->last_rgba_gpu = rgba_gpu;
            ctx->has_gpu_frame = true;
            
            // Legacy path support
            int rgba_size = rgba_gpu.cols * rgba_gpu.rows * 4;
            if (ctx->rgba_buffer.size() != rgba_size) ctx->rgba_buffer.resize(rgba_size);
            
            if (ctx->texture_manager_id == 0 && ctx->texture_id == 0) {
                cv::Mat rgba_cpu_for_legacy(rgba_gpu.rows, rgba_gpu.cols, CV_8UC4, ctx->rgba_buffer.data());
                rgba_gpu.download(rgba_cpu_for_legacy);
            }
            
            av_frame_unref(ctx->frame);
            *width = src_width;
            *height = src_height;
            *out_buffer = ctx->rgba_buffer.data();
            return 0;
            
        } catch (const cv::Exception& e) {
            ctx->use_gpu_texture = false;
        }
    }

    // CPU Fallback
    if (ctx->frame->format == AV_PIX_FMT_CUDA) {
        if (av_hwframe_transfer_data(ctx->sw_frame, ctx->frame, 0) < 0) {
            av_frame_unref(ctx->frame);
            return 2;
        }
        av_frame_copy_props(ctx->sw_frame, ctx->frame);
    } else {
        av_frame_unref(ctx->sw_frame);
        av_frame_move_ref(ctx->sw_frame, ctx->frame);
    }
    
    // Convert to RGBA
    int src_width = ctx->sw_frame->width;
    int src_height = ctx->sw_frame->height;
    int dst_width = src_width;
    int dst_height = src_height;
    
    // Downscale fallback if too large for CPU - REMOVED for quality
    // if (src_width > 320) {
    //      float scale = 320.0f / src_width;
    //      dst_width = 320;
    //      dst_height = (int)(src_height * scale);
    // }
    
    if (!ctx->sws_ctx || dst_width != ctx->last_width || dst_height != ctx->last_height || (int)ctx->sw_frame->format != ctx->last_format) {
         if (ctx->sws_ctx) sws_freeContext(ctx->sws_ctx);
         ctx->sws_ctx = sws_getContext(src_width, src_height, (AVPixelFormat)ctx->sw_frame->format, dst_width, dst_height, AV_PIX_FMT_RGBA, SWS_FAST_BILINEAR, nullptr, nullptr, nullptr);
         ctx->last_width = dst_width;
         ctx->last_height = dst_height;
         ctx->last_format = (int)ctx->sw_frame->format;
    }
    
    size_t rgba_size = dst_width * dst_height * 4;
    if (ctx->rgba_buffer.size() != rgba_size) ctx->rgba_buffer.resize(rgba_size);
    
    uint8_t* dst_data[1] = { ctx->rgba_buffer.data() };
    int dst_linesize[1] = { dst_width * 4 };
    
    sws_scale(ctx->sws_ctx, ctx->sw_frame->data, ctx->sw_frame->linesize, 0, src_height, dst_data, dst_linesize);
    av_frame_unref(ctx->sw_frame);
    
    *width = dst_width;
    *height = dst_height;
    *out_buffer = ctx->rgba_buffer.data();
    
    return 0;

#else
    // OpenCV Fallback
    if (out_timestamp) *out_timestamp = (int64_t)ctx->cap->get(cv::CAP_PROP_POS_MSEC);
    
    bool success = ctx->cap->read(ctx->last_frame);
    if (!success || ctx->last_frame.empty()) {
        ctx->cap->set(cv::CAP_PROP_POS_FRAMES, 0);
        success = ctx->cap->read(ctx->last_frame);
        if (!success) return 2;
    }
    
    cv::Mat rgb_frame;
    cv::cvtColor(ctx->last_frame, rgb_frame, cv::COLOR_BGR2RGBA);
    size_t dataSize = rgb_frame.total() * rgb_frame.elemSize();
    if (ctx->rgb_buffer.size() != dataSize) ctx->rgb_buffer.resize(dataSize);
    std::memcpy(ctx->rgb_buffer.data(), rgb_frame.data, dataSize);
    
    *width = rgb_frame.cols;
    *height = rgb_frame.rows;
    *out_buffer = ctx->rgb_buffer.data();
    
    return 0;
#endif
}
