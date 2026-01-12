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

import android.view.Surface
import io.flutter.view.TextureRegistry

class FFmpegVideoPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var textureRegistry: TextureRegistry
    private val streams = ConcurrentHashMap<Int, FFmpegStream>()
    private var nextId = AtomicInteger(1)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "ffmpeg_video")
        channel.setMethodCallHandler(this)
        textureRegistry = binding.textureRegistry
        
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
                        val textureEntry = textureRegistry.createSurfaceTexture()
                        val textureId = textureEntry.id()
                        val stream = FFmpegStream(url, id, textureEntry)
                        streams[id] = stream
                        stream.start()
                        result.success(mapOf("videoId" to id, "textureId" to textureId))
                    } catch (e: Exception) {
                        result.error("OPEN_ERROR", e.message, null)
                    }
                } else {
                    result.error("INVALID_ARGS", "URL required", null)
                }
            }
            "showFrame" -> {
                val id = call.argument<Int>("id")
                // Parsing Long from MethodChannel arguments needs care (Int vs Long)
                val timestampObj = call.argument<Any>("timestamp")
                val timestamp = if (timestampObj is Number) timestampObj.toLong() else null
                
                if (id != null && timestamp != null && streams.containsKey(id)) {
                    streams[id]!!.showFrame(timestamp)
                    result.success(null)
                } else {
                    result.error("INVALID_ARGS", "Stream $id or TS $timestamp not found", null)
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
                    result.error("INVALID_ID", "Stream $id not found", null)
                }
            }
            "releaseVideo" -> {
                val id = call.argument<Int>("id")
                if (id != null && streams.containsKey(id)) {
                    streams[id]!!.stop()
                    streams.remove(id)
                    result.success(null)
                } else {
                    result.success(null)
                }
            }
            else -> result.notImplemented()
        }
    }
}

class FFmpegStream(
    private val url: String, 
    private val id: Int, 
    private val textureEntry: TextureRegistry.SurfaceTextureEntry
) {
    private val isRunning = AtomicBoolean(false)
    private var latestFrame: Map<String, Any>? = null
    private val frameLock = Object()
    private val converter = AndroidFrameConverter()
    
    // Buffer for Render-on-Demand
    private val frameBuffer = ConcurrentHashMap<Long, Bitmap>()
    
    // Inference Buffer (still needed for zero-copy-ish transfer to Dart)
    private var bufferA: ByteArray? = null
    private var bufferB: ByteArray? = null
    private var useBufferA = true
    
    fun start() {
        if (isRunning.getAndSet(true)) return
        
        thread {
            android.util.Log.i("FFmpegStream", "Starting buffered stream $id: $url")
            
            val surfaceTexture = textureEntry.surfaceTexture()
            surfaceTexture.setDefaultBufferSize(1280, 720) // High Res
            // Note: We don't need a Surface object permanently in the loop anymore,
            // we will create/use it inside showFrame or keep it here?
            // Keeping it here is safer for the generic cleanup.
            // Wait, we need the Surface to draw.
            // Let's create it once.
            val surface = Surface(surfaceTexture)
             
            var grabber: FFmpegFrameGrabber? = null
            
            try {
                val g = FFmpegFrameGrabber(url)
                grabber = g
                if (url.startsWith("rtsp")) {
                    g.setFormat("rtsp")
                    g.setOption("rtsp_transport", "tcp")
                    g.setOption("stimeout", "5000000")
                }
                g.setOption("threads", "1")
                g.setImageWidth(1280)
                g.setImageHeight(720)
                g.setPixelFormat(avutil.AV_PIX_FMT_RGBA)
                g.setAudioChannels(0)
                
                g.start()
                android.util.Log.i("FFmpegStream", "✓ Grabber started")

                // Determine Frame Rate for Pacing (Files only)
                var targetDelay = 0L
                if (!url.startsWith("rtsp")) {
                    val fps = g.frameRate
                    if (fps > 0) {
                        targetDelay = (1000.0 / fps).toLong()
                        android.util.Log.i("FFmpegStream", "File pacing: ${fps}fps -> ${targetDelay}ms delay")
                    }
                }
                
                while (isRunning.get()) {
                    val loopStart = System.currentTimeMillis()
                    
                    val frame = grabber?.grabImage()
                    if (frame == null || frame.image == null) {
                         // EOF Handling: Loop video if file
                         if (!url.startsWith("rtsp")) {
                             try {
                                 g.restart() 
                                 continue
                             } catch(e: Exception) {}
                         }
                         
                         Thread.sleep(100)
                         continue
                    }
                    
                    // Generate Timestamp (Microseconds)
                    val timestamp = frame.timestamp 
                    
                    // 1. Buffer Bitmap for Display (Render-on-Demand)
                    val rawBitmap = converter.convert(frame)
                    if (rawBitmap != null) {
                        // Create a managed copy for the buffer
                        val storedBitmap = rawBitmap.copy(Bitmap.Config.ARGB_8888, false)
                        frameBuffer[timestamp] = storedBitmap
                        
                        // Prune buffer (Max 6 frames)
                        if (frameBuffer.size > 6) {
                            val minKey = frameBuffer.keys().asSequence().minOrNull()
                            if (minKey != null) {
                                val old = frameBuffer.remove(minKey)
                                old?.recycle()
                            }
                        }
                    }
                    
                    // 2. Prepare Data for Dart (Inference)
                    // Throttle sending to Dart? (e.g. max 15fps) to save bandwidth?
                    // Currently relying on Dart's async queue to backpressure.
                    
                    val w = frame.imageWidth
                    val h = frame.imageHeight
                    
                    // Byte Extraction Logic
                    val len = w * h * 4
                    if (bufferA == null || bufferA!!.size != len) {
                        bufferA = ByteArray(len)
                        bufferB = ByteArray(len)
                    }
                    val currentBuffer = if (useBufferA) bufferA!! else bufferB!!
                    useBufferA = !useBufferA
                    
                    var success = false
                     if (frame.image != null && frame.image.isNotEmpty()) {
                        try {
                            val buffer = frame.image[0] as? java.nio.ByteBuffer
                            if (buffer != null && buffer.capacity() >= len) {
                                buffer.position(0)
                                buffer.get(currentBuffer, 0, len)
                                success = true
                            }
                        } catch(e: Exception) {}
                    }
                    
                    if (success) {
                         synchronized(frameLock) {
                             latestFrame = mapOf(
                                 "width" to w,
                                 "height" to h,
                                 "data" to currentBuffer,
                                 "timestamp" to timestamp
                             )
                         }
                    }
                    
                    // Cleanup old frames
                    if (frameBuffer.size > 6) {
                         val min = frameBuffer.keys().asSequence().minOrNull()
                         if (min != null) frameBuffer.remove(min)?.recycle()
                    }
                    
                    // 3. Pacing (Sleep)
                    if (targetDelay > 0) {
                        // Subtract processing time for accuracy
                        val elapsed = System.currentTimeMillis() - loopStart
                        val sleep = targetDelay - elapsed
                        if (sleep > 0) Thread.sleep(sleep)
                    } else {
                        Thread.sleep(5) // Default poll
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("FFmpegStream", "Loop error: $e")
            } finally {
                grabber?.stop()
                grabber?.release()
                surface.release()
                textureEntry.release()
            }
        }
    }
    
    fun showFrame(timestamp: Long) {
        val bitmap = frameBuffer.remove(timestamp) // Get and remove (consume)
        if (bitmap != null) {
            try {
                val surfaceTexture = textureEntry.surfaceTexture()
                // Need a surface. Can we create one on fly or reuse?
                // Surface(surfaceTexture) is cheap?
                // Ideally reuse. But we can't pass it easily.
                // Let's make `surface` a member? Thread safety?
                // Surface is thread safe.
                val surface = Surface(surfaceTexture)
                
                val rect = android.graphics.Rect(0, 0, 1280, 720)
                val canvas = surface.lockCanvas(rect)
                canvas.drawBitmap(bitmap, null, rect, null)
                surface.unlockCanvasAndPost(canvas)
                
                surface.release() // Release scope
                bitmap.recycle() // Done with it
            } catch (e: Exception) {
                android.util.Log.e("FFmpegStream", "Show error: $e")
            }
        } else {
             android.util.Log.w("FFmpegStream", "Frame $timestamp not found in buffer")
        }
    }

    fun getLatestFrame(): Map<String, Any>? {
        synchronized(frameLock) {
            val frame = latestFrame
            latestFrame = null
            return frame
        }
    }

    fun stop() {
        isRunning.set(false)
    }
}
