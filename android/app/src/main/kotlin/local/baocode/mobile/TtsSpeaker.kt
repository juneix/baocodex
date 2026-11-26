package local.baocode.mobile

import android.content.Context
import android.speech.tts.TextToSpeech
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** 封装系统自带 TextToSpeech 引擎，不依赖第三方插件或网络接口。 */
class TtsSpeaker(private val context: Context) : TextToSpeech.OnInitListener, AutoCloseable {
    private var tts: TextToSpeech? = null
    private var ready = false
    private var initFailed = false
    private var utteranceSeq = 0L
    private var pending: PendingSpeak? = null

    private data class PendingSpeak(
        val text: String,
        val voice: String?,
        val rate: Float,
        val result: MethodChannel.Result,
    )

    private fun ensureEngine(): TextToSpeech? {
        if (initFailed) return null
        val existing = tts
        if (existing != null) return existing
        val created = TextToSpeech(context.applicationContext, this)
        tts = created
        return created
    }

    override fun onInit(status: Int) {
        if (status != TextToSpeech.SUCCESS) {
            initFailed = true
            ready = false
            pending?.result?.success(false)
            pending = null
            return
        }
        ready = true
        val queued = pending ?: return
        pending = null
        runSpeak(queued.text, queued.voice, queued.rate, queued.result)
    }

    fun speak(call: MethodCall, result: MethodChannel.Result) {
        val text = call.argument<String>("text")?.trim().orEmpty()
        if (text.isEmpty()) {
            result.success(false)
            return
        }
        val voice = call.argument<String>("voice")?.takeIf { it.isNotBlank() }
        val rate = ((call.argument<Number>("rate")?.toFloat()) ?: 1.0f).coerceIn(0.5f, 2.0f)
        val engine = ensureEngine()
        if (engine == null) {
            result.success(false)
            return
        }
        if (!ready) {
            pending?.result?.success(false)
            pending = PendingSpeak(text, voice, rate, result)
            return
        }
        runSpeak(text, voice, rate, result)
    }

    private fun runSpeak(
        text: String,
        voiceName: String?,
        rate: Float,
        result: MethodChannel.Result,
    ) {
        val engine = tts ?: run {
            result.success(false)
            return
        }
        engine.setSpeechRate(rate)
        if (voiceName != null) {
            val matched = runCatching {
                engine.voices?.firstOrNull { it.name == voiceName }
            }.getOrNull()
            if (matched != null) engine.voice = matched
        }
        val id = "baocodex_tts_${++utteranceSeq}"
        val code = engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, id)
        result.success(code == TextToSpeech.SUCCESS)
    }

    fun stop(result: MethodChannel.Result) {
        pending?.result?.success(false)
        pending = null
        runCatching { tts?.stop() }
        result.success(null)
    }

    fun voices(result: MethodChannel.Result) {
        val engine = ensureEngine()
        if (engine == null || !ready) {
            result.success(emptyList<Map<String, Any>>())
            return
        }
        val list = runCatching {
            engine.voices
                ?.asSequence()
                ?.filter { !it.isNetworkConnectionRequired }
                ?.sortedWith(compareBy({ it.locale.toLanguageTag() }, { it.name }))
                ?.map {
                    mapOf(
                        "name" to it.name,
                        "locale" to it.locale.toLanguageTag(),
                    )
                }
                ?.toList()
                ?: emptyList()
        }.getOrDefault(emptyList())
        result.success(list)
    }

    override fun close() {
        pending?.result?.success(false)
        pending = null
        runCatching {
            tts?.stop()
            tts?.shutdown()
        }
        tts = null
        ready = false
    }
}
