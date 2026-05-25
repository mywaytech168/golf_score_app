package com.ymd.flutter_audio_capture

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import android.os.Handler
import android.os.Looper

import io.flutter.plugin.common.EventChannel.StreamHandler
import io.flutter.plugin.common.EventChannel.EventSink
import java.lang.Exception

public class AudioCaptureStreamHandler: StreamHandler {
    public val eventChannelName = "ymd.dev/audio_capture_event_channel"
    public var actualSampleRate: Int = 0

    private val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
    private val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_FLOAT
    private var AUDIO_SOURCE: Int = MediaRecorder.AudioSource.DEFAULT
    private var SAMPLE_RATE: Int = 44000
    private val TAG: String = "AudioCaptureStream"
    private var isCapturing: Boolean = false
    private var listener = null
    private var thread: Thread? = null
    private var _events: EventSink? = null
    private val uiThreadHandler: Handler = Handler(Looper.getMainLooper())

    override fun onListen(arguments: Any?, events: EventSink?) {
        Log.d(TAG, "onListen started")
        if (arguments != null && arguments is Map<*, *>) {
            val sampleRate = arguments["sampleRate"]
            if (sampleRate != null && sampleRate is Int) {
                SAMPLE_RATE = sampleRate
            }
            val audioSource = arguments["audioSource"]
            if (audioSource != null && audioSource is Int) {
                AUDIO_SOURCE = audioSource
            }
        }

        this._events = events
        startRecording()
    }

    override fun onCancel(p0: Any?) {
        Log.d(TAG, "onListen canceled")
        stopRecording()
    }

    public fun startRecording() {
        if (thread != null) {
            Log.d(TAG, "startRecording called but thread is not null, returning.")
            return
        }

        isCapturing = true
        val runnableObj: Runnable = object: Runnable {
            override public fun run() {
                record()
            }
        }
        thread = Thread(runnableObj)
        thread?.start()
    }

    public fun stopRecording() {
        if (thread == null) {
            Log.d(TAG, "stopRecording called but thread is already null, returning.")
            return
        }
        Log.d(TAG, "stopRecording called, setting isCapturing to false.")
        isCapturing = false

        actualSampleRate = 1 // -> we are currently stopping
        try {
            thread?.join(5000)
            Log.d(TAG, "thread.join() completed.")
        } catch (e: InterruptedException) {
            Log.e(TAG, "thread.join() interrupted.", e)
        }
        thread = null
        actualSampleRate = 2 // -> we are stopped
        Log.d(TAG, "stopRecording finished, thread is now null.")
    }

    private fun sendError(key: String?, msg: String?) {
        uiThreadHandler.post(object: Runnable {
            override fun run() {
                if (isCapturing) {
                    _events?.error(key, msg, null)
                }
            }
        })
    }

    private fun sendBuffer(audioBuffer: ArrayList<FloatArray>, bufferIndex: Int) {
        uiThreadHandler.post(object: Runnable {
            var index: Int = -1

            override fun run() {
                if (isCapturing) {
                    val data = mapOf(
                        "actualSampleRate" to actualSampleRate.toDouble(),
                        "audioData" to audioBuffer[index]
                    )
                    _events?.success(data)
                }
            }

            public fun init(idx: Int): Runnable {
                this.index = idx
                return this
            }

        }.init(bufferIndex))
    }

    // ── 建立 AudioRecord：先嘗試 PCM_FLOAT，失敗後 fallback 至 PCM_16BIT ──
    private data class AudioSetup(
        val record: AudioRecord,
        val frameCount: Int,
        val useFloat: Boolean
    )

    private fun createAudioRecord(): AudioSetup? {
        // 1. 嘗試 PCM_FLOAT（原始格式，精度最高）
        val floatBufBytes = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
        if (floatBufBytes > 0) {
            try {
                val r = AudioRecord.Builder()
                    .setAudioSource(AUDIO_SOURCE)
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AUDIO_FORMAT)
                            .setSampleRate(SAMPLE_RATE)
                            .setChannelMask(CHANNEL_CONFIG)
                            .build()
                    )
                    .setBufferSizeInBytes(floatBufBytes)
                    .build()
                Log.d(TAG, "AudioRecord created with PCM_FLOAT, bufBytes=$floatBufBytes")
                // floatBufBytes 是 byte 數，每個 Float = 4 bytes
                return AudioSetup(r, floatBufBytes / 4, true)
            } catch (e: Exception) {
                Log.e(TAG, "PCM_FLOAT AudioRecord failed: ${e.message}, trying PCM_16BIT fallback")
            }
        }

        // 2. Fallback：PCM_16BIT（幾乎所有裝置都支援）
        val pcm16BufBytes = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AudioFormat.ENCODING_PCM_16BIT)
        if (pcm16BufBytes > 0) {
            try {
                val r = AudioRecord.Builder()
                    .setAudioSource(AUDIO_SOURCE)
                    .setAudioFormat(
                        AudioFormat.Builder()
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .setSampleRate(SAMPLE_RATE)
                            .setChannelMask(CHANNEL_CONFIG)
                            .build()
                    )
                    .setBufferSizeInBytes(pcm16BufBytes)
                    .build()
                Log.d(TAG, "AudioRecord created with PCM_16BIT fallback, bufBytes=$pcm16BufBytes")
                // pcm16BufBytes 是 byte 數，每個 Short = 2 bytes
                return AudioSetup(r, pcm16BufBytes / 2, false)
            } catch (e: Exception) {
                Log.e(TAG, "PCM_16BIT AudioRecord also failed: ${e.message}")
            }
        }

        return null
    }

    private fun record() {
        android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_AUDIO)

        // ── 建立錄音器（有 try-catch，失敗時優雅降級而非 crash）────────────
        val setup = createAudioRecord()
        if (setup == null) {
            Log.e(TAG, "No AudioRecord could be created, aborting recording")
            sendError("AUDIO_RECORD_INITIALIZE_ERROR", "Cannot create AudioRecord on this device")
            isCapturing = false
            return
        }

        val (record, frameCount, useFloat) = setup
        val bufferCount = 10
        var bufferIndex = 0
        val audioBuffer = ArrayList<FloatArray>()

        for (i in 1..bufferCount) {
            audioBuffer.add(FloatArray(frameCount))
        }

        if (record.state != AudioRecord.STATE_INITIALIZED) {
            Log.e(TAG, "AudioRecord STATE_UNINITIALIZED after build")
            sendError("AUDIO_RECORD_INITIALIZE_ERROR", "AudioRecord can't initialize")
            record.release()
            isCapturing = false
            return
        }

        record.startRecording()
        actualSampleRate = record.sampleRate

        while (record.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
            Thread.yield()
        }

        Log.d(TAG, "Recording started: useFloat=$useFloat, actualSampleRate=$actualSampleRate, frameCount=$frameCount")

        // ── PCM_16BIT 時需要中間 ShortArray 做格式轉換 ────────────────────
        val shortBuf: ShortArray? = if (useFloat) null else ShortArray(frameCount)

        while (isCapturing) {
            try {
                if (useFloat) {
                    record.read(audioBuffer[bufferIndex], 0, frameCount, AudioRecord.READ_BLOCKING)
                } else {
                    // PCM_16BIT → 轉換為 [-1.0, 1.0] FloatArray
                    record.read(shortBuf!!, 0, frameCount)
                    for (i in 0 until frameCount) {
                        audioBuffer[bufferIndex][i] = shortBuf[i] / 32768.0f
                    }
                }
                sendBuffer(audioBuffer, bufferIndex)
            } catch (e: Exception) {
                Log.d(TAG, "read error: $e")
                sendError("AUDIO_RECORD_READ_ERROR", "AudioRecord can't read")
                Thread.yield()
            }
            bufferIndex = (bufferIndex + 1) % bufferCount
        }

        record.stop()
        record.release()
        Log.d(TAG, "Recording stopped and released")
    }
}
