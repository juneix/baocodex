package local.baocode.mobile

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** 封装系统自带 TextToSpeech 引擎与轻量本地音频播放，不依赖第三方插件。 */
class TtsSpeaker(private val context: Context) : TextToSpeech.OnInitListener, AutoCloseable {
    private val main = Handler(Looper.getMainLooper())
    private var tts: TextToSpeech? = null
    private var player: MediaPlayer? = null
    private var ready = false
    private var initFailed = false
    private var utteranceSeq = 0L
    private var pending: PendingSpeak? = null
    private val pendingVoices = mutableListOf<MethodChannel.Result>()
    private var activeSpeakId: String? = null
    private var activeSpeakResult: MethodChannel.Result? = null
    private var activePlayResult: MethodChannel.Result? = null

    private data class PendingSpeak(
        val text: String,
        val voice: String?,
        val rate: Float,
        val pitch: Float,
        val result: MethodChannel.Result,
    )

    private fun ensureEngine(): TextToSpeech? {
        if (initFailed) return null
        val existing = tts
        if (existing != null) return existing
        val created = TextToSpeech(context.applicationContext, this)
        created.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}

            override fun onDone(utteranceId: String?) {
                main.post { finishActiveSpeak(utteranceId, true) }
            }

            @Deprecated("Deprecated in API 21")
            override fun onError(utteranceId: String?) {
                main.post { finishActiveSpeak(utteranceId, false) }
            }

            override fun onError(utteranceId: String?, errorCode: Int) {
                main.post { finishActiveSpeak(utteranceId, false) }
            }

            override fun onStop(utteranceId: String?, interrupted: Boolean) {
                main.post { finishActiveSpeak(utteranceId, false) }
            }
        })
        tts = created
        return created
    }

    private fun finishActiveSpeak(utteranceId: String?, ok: Boolean) {
        if (utteranceId != null && utteranceId != activeSpeakId) return
        val res = activeSpeakResult ?: return
        activeSpeakResult = null
        activeSpeakId = null
        res.success(ok)
    }

    private fun finishActivePlay(ok: Boolean) {
        val res = activePlayResult ?: return
        activePlayResult = null
        res.success(ok)
    }

    override fun onInit(status: Int) {
        if (status != TextToSpeech.SUCCESS) {
            Log.w("TtsSpeaker", "TextToSpeech init failed with status=$status")
            initFailed = true
            ready = false
            pending?.result?.success(false)
            pending = null
            flushPendingVoices()
            return
        }
        ready = true
        flushPendingVoices()
        val queued = pending ?: return
        pending = null
        runSpeak(queued.text, queued.voice, queued.rate, queued.pitch, queued.result)
    }

    fun speak(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text")?.trim().orEmpty()
        if (text.isEmpty()) {
            result.success(false)
            return
        }
        val voice = call.argument<String>("voice")?.takeIf { it.isNotBlank() }
        val rate = ((call.argument<Number>("rate")?.toFloat()) ?: 1.0f).coerceIn(0.5f, 2.0f)
        val pitch = ((call.argument<Number>("pitch")?.toFloat()) ?: 1.0f).coerceIn(0.5f, 1.5f)
        val engine = ensureEngine()
        if (engine == null) {
            result.success(false)
            return
        }
        if (!ready) {
            pending?.result?.success(false)
            pending = PendingSpeak(text, voice, rate, pitch, result)
            return
        }
        runSpeak(text, voice, rate, pitch, result)
    }

    private fun runSpeak(
        text: String,
        voiceName: String?,
        rate: Float,
        pitch: Float,
        result: MethodChannel.Result,
    ) {
        val engine = tts ?: run {
            result.success(false)
            return
        }
        stopPlayback()
        engine.setSpeechRate(rate)
        engine.setPitch(pitch)
        if (voiceName != null) {
            val matched = runCatching {
                engine.voices?.firstOrNull { it.name == voiceName }
            }.getOrNull()
            if (matched != null) engine.voice = matched
        }
        val id = "baocodex_tts_${++utteranceSeq}"
        activeSpeakId = id
        activeSpeakResult = result
        val code = engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, id)
        if (code != TextToSpeech.SUCCESS) {
            finishActiveSpeak(id, false)
        }
    }

    fun stop(result: MethodChannel.Result) {
        pending?.result?.success(false)
        pending = null
        stopPlayback()
        result.success(null)
    }

    private fun stopPlayback() {
        finishActiveSpeak(activeSpeakId, false)
        finishActivePlay(false)
        runCatching { tts?.stop() }
        runCatching {
            player?.let {
                if (it.isPlaying) it.stop()
                it.release()
            }
        }
        player = null
    }

    fun playAudio(call: MethodCall, result: MethodChannel.Result) {
        val bytes = call.argument<ByteArray>("bytes")
        val ext = call.argument<String>("ext")?.takeIf { it == "mp3" || it == "wav" } ?: "mp3"
        if (bytes == null || bytes.isEmpty()) {
            result.success(false)
            return
        }
        stopPlayback()
        try {
            val file = File(context.cacheDir, "baocodex_tts_audio.$ext")
            file.writeBytes(bytes)
            activePlayResult = result
            val mp = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                )
                setDataSource(file.absolutePath)
                setOnCompletionListener {
                    runCatching { it.release() }
                    if (player === it) player = null
                    finishActivePlay(true)
                }
                setOnErrorListener { failed, _, _ ->
                    runCatching { failed.release() }
                    if (player === failed) player = null
                    finishActivePlay(false)
                    true
                }
                prepare()
                start()
            }
            player = mp
        } catch (error: Exception) {
            Log.w("TtsSpeaker", "playAudio failed: ${error.message}")
            stopPlayback()
        }
    }

    fun voices(result: MethodChannel.Result) {
        val engine = ensureEngine()
        if (engine == null) {
            result.success(emptyList<Map<String, Any>>())
            return
        }
        if (!ready) {
            pendingVoices.add(result)
            return
        }
        result.success(collectVoices(engine))
    }

    private fun flushPendingVoices() {
        if (pendingVoices.isEmpty()) return
        val waiting = pendingVoices.toList()
        pendingVoices.clear()
        val list = if (ready) tts?.let(::collectVoices) ?: emptyList() else emptyList()
        waiting.forEach { it.success(list) }
    }

    private fun collectVoices(engine: TextToSpeech): List<Map<String, Any>> = runCatching {
        engine.voices
            ?.asSequence()
            ?.sortedWith(
                compareBy<android.speech.tts.Voice>(
                    { !it.locale.language.equals("zh", ignoreCase = true) },
                    { it.isNetworkConnectionRequired },
                    { it.locale.toLanguageTag() },
                    { it.name },
                )
            )
            ?.map {
                mapOf(
                    "name" to it.name,
                    "locale" to it.locale.toLanguageTag(),
                    "network" to it.isNetworkConnectionRequired,
                )
            }
            ?.toList()
            ?: emptyList()
    }.getOrDefault(emptyList())

    override fun close() {
        pending?.result?.success(false)
        pending = null
        flushPendingVoices()
        stopPlayback()
        runCatching { tts?.shutdown() }
        tts = null
        ready = false
    }
}
