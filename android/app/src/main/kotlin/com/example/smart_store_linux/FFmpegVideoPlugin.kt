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
    private lateinit var applicationContext: android.content.Context
    private val streams = ConcurrentHashMap<Int, FFmpegStream>()
    private var nextId = AtomicInteger(1)
    private var npuStatsDisabled = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "ffmpeg_video")
        channel.setMethodCallHandler(this)
        textureRegistry = binding.textureRegistry
        applicationContext = binding.applicationContext
        
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
                    val success = streams[id]!!.showFrame(timestamp)
                    result.success(success)
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
            "getSystemStats" -> {
                 thread {
                     try {
                         // 1. NPU Stats (Rockchip specific)
                         // 1. NPU Stats (Rockchip specific)
                         var npuLoad = 0.0
                         if (!npuStatsDisabled) {
                             val paths = listOf(
                                 "/sys/kernel/debug/rknpu/load",
                                 "/sys/class/devfreq/fdab0000.npu/load"
                             )
                             
                             for (path in paths) {
                                 try {
                                     val file = java.io.File(path)
                                     if (file.exists() && file.canRead()) {
                                         val content = file.readText().trim()
                                         // android.util.Log.v("FFmpegVideoPlugin", "NPU raw ($path): '$content'") // Verbose only
                                         
                                         // Robust parsing for multi-core: "NPU load:  Core0: 15%, Core1:  0%, Core2:  0%,"
                                         val percentMatches = Regex("(\\d+)%").findAll(content)
                                         
                                         var sumLoad = 0.0
                                         var count = 0
                                         
                                         for (match in percentMatches) {
                                             val (valStr) = match.destructured
                                             val v = valStr.toDoubleOrNull() ?: 0.0
                                             sumLoad += v
                                             count++
                                         }
                                         
                                         if (count > 0) {
                                             npuLoad = sumLoad / count
                                             break
                                         }
                                     }
                                 } catch(e: Exception) {
                                     android.util.Log.w("FFmpegVideoPlugin", "Failed to read $path (Disabling NPU stats): $e")
                                     npuStatsDisabled = true // Fail fast: disable subsequent attempts
                                 }
                             }
                         }
                         
                         // 2. RAM Stats
                         val actManager = applicationContext.getSystemService(android.content.Context.ACTIVITY_SERVICE) as android.app.ActivityManager
                         val memInfo = android.app.ActivityManager.MemoryInfo()
                         actManager.getMemoryInfo(memInfo)
                         val totalRamGb = memInfo.totalMem.toDouble() / (1024 * 1024 * 1024)
                         val availRamGb = memInfo.availMem.toDouble() / (1024 * 1024 * 1024)
                         val usedRamGb = totalRamGb - availRamGb
                         
                         // 3. CPU Stats (Rough estimate from /proc/stat)
                         // Getting accurate per-app CPU on Android 8+ is hard restricted.
                         // But we can try system-wide load if accessible or simulated.
                         // Simple approach: Read /proc/stat if generic linux kernel accessible
                         var cpuLoad = 0.0
                         try {
                              // Simplified one-shot - reliable delta requires state
                              // For now, return 0.0 or random fluctuation?
                              // Let's rely on Dart side for simulated CPU if native fails, 
                              // or just return 0 if restricted.
                         } catch(e: Exception) {}

                         val stats = mapOf(
                             "npu" to npuLoad, // The "GPU" field in Dart will show this
                             "ram" to usedRamGb,
                             "ramTotal" to totalRamGb,
                             "cpu" to 0.0 // Placeholder
                         )
                         
                         android.os.Handler(android.os.Looper.getMainLooper()).post {
                             result.success(stats)
                         }
                     } catch (e: Exception) {
                         android.os.Handler(android.os.Looper.getMainLooper()).post {
                             result.error("STATS_ERROR", e.message, null)
                         }
                     }
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
    
    // Auto-Play Mode (Display immediately until first showFrame call)
    // This prevents black screen during model loading (2-3s delay)
    private val autoDisplay = AtomicBoolean(true)

    // Rendering Thread
    private val renderThread = android.os.HandlerThread("RenderThread-$id")
    private lateinit var renderHandler: android.os.Handler
    private var surface: Surface? = null // Reuse Surface
    
    init {
        renderThread.start()
        renderHandler = android.os.Handler(renderThread.looper)
    }
    
    fun start() {
        if (isRunning.getAndSet(true)) return
        
        thread {
            android.util.Log.i("FFmpegStream", "Starting buffered stream $id: $url")
            
            val surfaceTexture = textureEntry.surfaceTexture()
            surfaceTexture.setDefaultBufferSize(1280, 720) // High Res
            
            // Create Surface once for this stream
            synchronized(this) {
                surface = Surface(surfaceTexture)
            }
             
            var grabber: FFmpegFrameGrabber? = null
            
            try {
                val g = FFmpegFrameGrabber(url)
                grabber = g
                if (url.startsWith("rtsp")) {
                    g.setFormat("rtsp")
                    g.setOption("rtsp_transport", "tcp")
                    g.setOption("stimeout", "5000000")
                }
                
                // Low Latency Tuning (Aggressive startup)
                g.setOption("analyzeduration", "200000") // Analyze only 200ms
                g.setOption("probesize", "1024576")      // 1MB probe limit
                g.setOption("fflags", "nobuffer")        // Reduce input buffering
                g.setOption("flags", "low_delay")        // Low delay mode
                
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
                                 frameBuffer.clear() // Clear old frames (high timestamps) to prevent pruning new ones (low timestamps)
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
                        // 1a. Auto-Display (Warmup Phase)
                        if (autoDisplay.get()) {
                             // Create a dedicated copy for rendering to avoid threading issues
                             val displayCopy = rawBitmap.copy(Bitmap.Config.ARGB_8888, false)
                             postRender(displayCopy)
                        }

                        // 1b. Buffer Bitmap for Display (Render-on-Demand)
                        val storedBitmap = rawBitmap.copy(Bitmap.Config.ARGB_8888, false)
                        frameBuffer[timestamp] = storedBitmap
                        
                        // Prune buffer (Max 60 frames ~ 2 sec history)
                        if (frameBuffer.size > 60) {
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
                    if (frameBuffer.size > 60) {
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
                
                synchronized(this) {
                    surface?.release()
                    surface = null
                }
                
                renderThread.quitSafely() // Stop render thread
                
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    textureEntry.release()
                }
            }
        }
    }
    
    fun showFrame(timestamp: Long): Boolean {
        // Switch to synchronized mode on first command
        autoDisplay.set(false)
        
        val bitmap = frameBuffer.remove(timestamp) // Get and remove (consume)
        if (bitmap != null) {
            postRender(bitmap)
            return true
        } else {
             // android.util.Log.w("FFmpegStream", "Frame $timestamp not found in buffer")
             return false
        }
    }

    private fun postRender(bitmap: Bitmap) {
        // Offload rendering to background thread to avoid UI jank
        renderHandler.post {
            try {
                synchronized(this) {
                    if (surface != null && surface!!.isValid) {
                        val rect = android.graphics.Rect(0, 0, 1280, 720)
                        val canvas = surface!!.lockCanvas(rect)
                        if (canvas != null) {
                            canvas.drawBitmap(bitmap, null, rect, null)
                            surface!!.unlockCanvasAndPost(canvas)
                        }
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("FFmpegStream", "Render error: $e")
            } finally {
                bitmap.recycle() // Always recycle
            }
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

