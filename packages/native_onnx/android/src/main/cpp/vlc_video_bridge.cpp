#include <jni.h>
#include <string>
#include <android/log.h>
#include <vlc/vlc.h>
#include <vector>
#include <mutex>

#define LOG_TAG "VLCVideo"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

struct VideoContext {
    libvlc_instance_t* vlc;
    libvlc_media_player_t* player;
    libvlc_media_t* media;
    
    std::vector<uint8_t> frameBuffer;
    int width;
    int height;
    std::mutex frameMutex;
    bool hasNewFrame;
    
    VideoContext() : vlc(nullptr), player(nullptr), media(nullptr), 
                     width(0), height(0), hasNewFrame(false) {}
};

// VLC video lock callback
static void* vlc_lock(void* data, void** pixels) {
    VideoContext* ctx = (VideoContext*)data;
    ctx->frameMutex.lock();
    *pixels = ctx->frameBuffer.data();
    return nullptr;
}

// VLC video unlock callback  
static void vlc_unlock(void* data, void* picture, void* const* pixels) {
    VideoContext* ctx = (VideoContext*)data;
    ctx->hasNewFrame = true;
    ctx->frameMutex.unlock();
}

// VLC display callback (unused but required)
static void vlc_display(void* data, void* picture) {
    // No-op
}

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_example_native_1onnx_VLCVideo_openVideo(JNIEnv* env, jobject, jstring url) {
    const char* urlStr = env->GetStringUTFChars(url, nullptr);
    LOGI("Opening video: %s", urlStr);
    
    VideoContext* ctx = new VideoContext();
    
    // Initialize LibVLC
    const char* args[] = {
        "--no-audio",
        "--rtsp-tcp",  // Use TCP for RTSP
        "--network-caching=300"
    };
    ctx->vlc = libvlc_new(3, args);
    if (!ctx->vlc) {
        LOGE("Failed to create LibVLC instance");
        delete ctx;
        env->ReleaseStringUTFChars(url, urlStr);
        return 0;
    }
    
    // Create media
    ctx->media = libvlc_media_new_location(ctx->vlc, urlStr);
    if (!ctx->media) {
        LOGE("Failed to create media");
        libvlc_release(ctx->vlc);
        delete ctx;
        env->ReleaseStringUTFChars(url, urlStr);
        return 0;
    }
    
    // Create player
    ctx->player = libvlc_media_player_new_from_media(ctx->media);
    
    // Set default resolution (will be updated from stream)
    ctx->width = 1920;
    ctx->height = 1080;
    ctx->frameBuffer.resize(ctx->width * ctx->height * 4); // RGBA
    
    // Setup video callbacks
    libvlc_video_set_callbacks(ctx->player, vlc_lock, vlc_unlock, vlc_display, ctx);
    libvlc_video_set_format(ctx->player, "RGBA", ctx->width, ctx->height, ctx->width * 4);
    
    // Start playback
    libvlc_media_player_play(ctx->player);
    
    env->ReleaseStringUTFChars(url, urlStr);
    LOGI("Video opened successfully");
    return reinterpret_cast<jlong>(ctx);
}

JNIEXPORT jint JNICALL
Java_com_example_native_1onnx_VLCVideo_getFrame(
    JNIEnv* env, jobject, jlong ctxPtr, 
    jobject widthOut, jobject heightOut, jbyteArray dataOut) {
    
    VideoContext* ctx = reinterpret_cast<VideoContext*>(ctxPtr);
    if (!ctx || !ctx->player) return -1;
    
    // Wait for new frame (with timeout)
    if (!ctx->hasNewFrame) {
        return 1; // No new frame yet
    }
    
    ctx->frameMutex.lock();
    ctx->hasNewFrame = false;
    
    // Copy frame data
    env->SetByteArrayRegion(dataOut, 0, ctx->frameBuffer.size(),
                           reinterpret_cast<jbyte*>(ctx->frameBuffer.data()));
    
    ctx->frameMutex.unlock();
    
    return 0; // Success
}

JNIEXPORT void JNICALL
Java_com_example_native_1onnx_VLCVideo_closeVideo(JNIEnv* env, jobject, jlong ctxPtr) {
    VideoContext* ctx = reinterpret_cast<VideoContext*>(ctxPtr);
    if (ctx) {
        if (ctx->player) {
            libvlc_media_player_stop(ctx->player);
            libvlc_media_player_release(ctx->player);
        }
        if (ctx->media) libvlc_media_release(ctx->media);
        if (ctx->vlc) libvlc_release(ctx->vlc);
        delete ctx;
        LOGI("Video closed");
    }
}

} // extern "C"
