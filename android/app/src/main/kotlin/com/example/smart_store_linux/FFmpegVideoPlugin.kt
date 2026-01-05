package com.example.smart_store_linux

import android.graphics.Bitmap
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.bytedeco.javacv.FFmpegFrameGrabber
import org.bytedeco.javacv.FFmpegLogCallback
import org.bytedeco.javacv.AndroidFrameConverter
import org.bytedeco.javacv.Frame
import org.bytedeco.ffmpeg.global.avcodec
import org.bytedeco.ffmpeg.global.avutil
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

class FFmpegVideoPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private val streams = ConcurrentHashMap<Int, FFmpegStream>()
    private var nextId = AtomicInteger(1)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "ffmpeg_video")
        channel.setMethodCallHandler(this)
        
        // Enable detailed FFmpeg logging
        FFmpegLogCallback.set()
        avutil.av_log_set_level(avutil.AV_LOG_VERBOSE)
        android.util.Log.i("FFmpegVideoPlugin", "FFmpeg logging enabled")
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        streams.values.forEach { it.stop() }
        streams.clear()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "openVideo" -> {
                val url = call.argument<String>("url")
                if (url != null) {
                    val id = nextId.getAndIncrement()
                    try {
                        val stream = FFmpegStream(url, id)
                        streams[id] = stream
                        stream.start()
                        result.success(id)
                    } catch (e: Exception) {
                        result.error("OPEN_ERROR", e.message, null)
                    }
                } else {
                    result.error("INVALID_ARGS", "URL required", null)
                }
            }
            "getFrame" -> {
                val id = call.argument<Int>("id")
                if (id != null && streams.containsKey(id)) {
                    try {
                        val frame = streams[id]!!.getLatestFrame()
                        result.success(frame)
                    } catch (e: Exception) {
                        result.error("GET_FRAME_ERROR", e.message, null)
                    }
                } else {
                    result.error("INVALID_ID", "Stream not found", null)
                }
            }
            "releaseVideo" -> {
                val id = call.argument<Int>("id")
                if (id != null && streams.containsKey(id)) {
                    streams[id]!!.stop()
                    streams.remove(id)
                    result.success(null)
                } else {
                    result.error("INVALID_ID", "Stream not found", null)
                }
            }
            else -> result.notImplemented()
        }
    }
}

class FFmpegStream(private val url: String, private val id: Int) {
    private val isRunning = AtomicBoolean(false)
    private var latestFrame: Map<String, Any>? = null
    private val frameLock = Object()
    private val converter = AndroidFrameConverter()
    private var skippedFrameCount = 0  // Track backpressure
    
    fun start() {
        if (isRunning.getAndSet(true)) return
        
        thread {
            android.util.Log.i("FFmpegStream", "Starting stream $id: $url")
            var grabber: FFmpegFrameGrabber? = null
            var frameGrabTries = 0
            try {
                // Configure grabber like working reference code
                val g = FFmpegFrameGrabber(url)
                grabber = g
                
                // RTSP specific options
                if (url.startsWith("rtsp")) {
                    g.setFormat("rtsp")
                    g.setOption("rtsp_transport", "tcp")
                    g.setOption("stimeout", "10000000") // 10 seconds timeout
                }
                
                g.setOption("threads", "1")
                
                // Image settings
                g.setImageWidth(1280)
                g.setImageHeight(720)
                g.setPixelFormat(avutil.AV_PIX_FMT_RGBA)
                
                g.setAudioChannels(0)  // disable audio
                
                android.util.Log.i("FFmpegStream", "Stream $id: Attempting to start grabber for $url")
                g.start()
                
                android.util.Log.i("FFmpegStream", "✓ Stream $id: Grabber started successfully")
                
                android.util.Log.i("FFmpegStream", "Stream $id: About to enter while loop, isRunning=${isRunning.get()}, interrupted=${Thread.currentThread().isInterrupted}")
                
                var frameCount = 0
                while (isRunning.get() && !Thread.currentThread().isInterrupted) {
                    try {
                        val frame: Frame? = grabber?.grabImage()
                        
                        // Check frame validity (from reference code)
                        if (frame == null || frame.image == null) {
                            android.util.Log.w("FFmpegStream", "Stream $id: Invalid frame encountered (EOF or error)")
                            
                            // For local files, this usually means EOF -> Loop immediately
                            // For RTSP, this usually means connection lost -> Reconnect
                            try {
                                android.util.Log.i("FFmpegStream", "Stream $id: Restarting stream...")
                                grabber?.stop()
                                grabber?.start()
                                android.util.Log.i("FFmpegStream", "Stream $id: Restart successful")
                                frameCount = 0 // Reset frame count for stats
                                continue
                            } catch (e: Exception) {
                                android.util.Log.e("FFmpegStream", "Stream $id: Restart failed: ${e.message}")
                                
                                if (frameGrabTries++ > 5) {
                                    android.util.Log.e("FFmpegStream", "Stream $id: Exceeded max retries")
                                    Thread.sleep(2000)
                                    frameGrabTries = 0 
                                }
                                Thread.sleep(100)
                                continue
                            }
                        }
                        
                        // Reset retry count on valid frame
                        frameGrabTries = 0
                        frameCount++
                        
                        // ✓ BACKPRESSURE: Only process frame if previous one was consumed
                        val shouldProcess = synchronized(frameLock) { latestFrame == null }
                        
                        if (!shouldProcess) {
                            // Skip frame to prevent memory buildup
                            skippedFrameCount++
                            if (skippedFrameCount % 100 == 0) {
                                android.util.Log.w("FFmpegStream", "Stream $id: $skippedFrameCount frames skipped (backpressure)")
                            }
                            continue
                        }
                        
                        // Reset skip counter when frame is processed
                        if (skippedFrameCount > 0 && frameCount % 100 == 0) {
                            android.util.Log.i("FFmpegStream", "Stream $id: Backpressure released, $skippedFrameCount frames skipped total")
                        }
                        
                        // Convert Frame → Bitmap
                        val bitmap = converter.convert(frame)
                        
                        if (bitmap != null) {
                            val w = bitmap.width
                            val h = bitmap.height
                            val pixels = IntArray(w * h)
                            bitmap.getPixels(pixels, 0, w, 0, 0, w, h)
                            
                            val rgba = ByteArray(w * h * 4)
                            for (i in pixels.indices) {
                                val pixel = pixels[i]
                                rgba[i * 4] = ((pixel shr 16) and 0xFF).toByte()
                                rgba[i * 4 + 1] = ((pixel shr 8) and 0xFF).toByte()
                                rgba[i * 4 + 2] = (pixel and 0xFF).toByte()
                                rgba[i * 4 + 3] = ((pixel shr 24) and 0xFF).toByte()
                            }
                            
                            synchronized(frameLock) {
                                latestFrame = mapOf(
                                    "width" to w,
                                    "height" to h,
                                    "data" to rgba
                                )
                            }
                            
                            // Log only every 100 frames to reduce overhead
                            if (frameCount % 100 == 0) {
                                android.util.Log.i("FFmpegStream", "✓ Stream $id: ${frameCount} frames captured")
                            }
                            
                            // DON'T recycle - AndroidFrameConverter manages bitmap pool
                        } else {
                            android.util.Log.w("FFmpegStream", "Stream $id: Bitmap conversion failed")
                        }
                    } catch (e: Exception) {
                        android.util.Log.e("FFmpegStream", "Stream $id: Frame processing error: ${e.message}", e)
                        Thread.sleep(100)
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("FFmpegStream", "Stream $id: Critical error: ${e.message}", e)
            } finally {
                try {
                    grabber?.stop()
                    grabber?.release()
                } catch (e: Exception) {
                    android.util.Log.e("FFmpegStream", "Stream $id: Cleanup error: ${e.message}")
                }
                android.util.Log.i("FFmpegStream", "Stream $id stopped")
            }
        }
    }
    
    fun getLatestFrame(): Map<String, Any>? {
        synchronized(frameLock) {
            val frame = latestFrame
            latestFrame = null  // Clear so next frame can be captured
            return frame
        }
    }
    
    fun stop() {
        isRunning.set(false)
    }
}
