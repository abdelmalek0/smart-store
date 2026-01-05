#include <jni.h>
#include <string>
#include <android/log.h>
#include <vector>
#include <mutex>

#define LOG_TAG "FFmpegVideo"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Simple frame capture using mobile-ffmpeg
// We'll use FFmpeg command-line to extract frames

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_example_smart_1store_1linux_FFmpegVideo_openVideo(JNIEnv* env, jobject, jstring url) {
    const char* urlStr = env->GetStringUTFChars(url, nullptr);
    LOGI("Opening video: %s", urlStr);
    
    // Return URL as context (simple approach)
    jlong ctx = reinterpret_cast<jlong>(strdup(urlStr));
    
    env->ReleaseStringUTFChars(url, urlStr);
    return ctx;
}

JNIEXPORT jbyteArray JNICALL
Java_com_example_smart_1store_1linux_FFmpegVideo_getFrame(JNIEnv* env, jobject, jlong ctxPtr) {
    // TODO: Use mobile-ffmpeg to extract frame
    // For now return null
    return nullptr;
}

JNIEXPORT void JNICALL
Java_com_example_smart_1store_1linux_FFmpegVideo_closeVideo(JNIEnv* env, jobject, jlong ctxPtr) {
    if (ctxPtr != 0) {
        char* url = reinterpret_cast<char*>(ctxPtr);
        free(url);
        LOGI("Video closed");
    }
}

} // extern "C"
