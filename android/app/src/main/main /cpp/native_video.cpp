#include <jni.h>
#include <string>
#include <android/log.h>

#define LOG_TAG "FFmpegVideo"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

extern "C" {

// Placeholder for FFmpeg headers - will add when libraries are available
// #include <libavformat/avformat.h>
// #include <libavcodec/avcodec.h>
// #include <libswscale/swscale.h>

struct VideoContext {
    void* formatCtx;
    void* codecCtx;
    void* swsCtx;
    int videoStream;
    int width;
    int height;
};

JNIEXPORT jlong JNICALL
Java_com_example_smart_1store_1linux_NativeVideo_openVideo(JNIEnv* env, jobject, jstring url) {
    const char* urlStr = env->GetStringUTFChars(url, nullptr);
    LOGI("Opening video: %s", urlStr);
    
    // For now, return placeholder
    VideoContext* ctx = new VideoContext();
    ctx->width = 1920;
    ctx->height = 1080;
    
    env->ReleaseStringUTFChars(url, urlStr);
    return reinterpret_cast<jlong>(ctx);
}

JNIEXPORT jintArray JNICALL
Java_com_example_smart_1store_1linux_NativeVideo_getFrame(JNIEnv* env, jobject, jlong ctxPtr) {
    // Placeholder - return null for now
    return nullptr;
}

JNIEXPORT void JNICALL
Java_com_example_smart_1store_1linux_NativeVideo_closeVideo(JNIEnv* env, jobject, jlong ctxPtr) {
    VideoContext* ctx = reinterpret_cast<VideoContext*>(ctxPtr);
    if (ctx) {
        LOGI("Closing video");
        delete ctx;
    }
}

} // extern "C"
