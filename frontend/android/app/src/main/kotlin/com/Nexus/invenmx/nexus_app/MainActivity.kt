package com.Nexus.invenmx.nexus_app

import android.content.Context
import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val dictationAudioChannel = "nexus/dictation_audio"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, dictationAudioChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setRecognizerBeepMuted" -> {
                        val mute = call.arguments as? Boolean ?: false
                        result.success(setRecognizerBeepMuted(mute))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // El reconocedor de voz de Google emite un tono en cada startListening y
    // el plugin speech_to_text no expone forma de apagarlo. Se mutea el stream
    // donde suena mientras el modal de dictado está escuchando; en qué stream
    // suena varía por fabricante (MUSIC en la mayoría).
    private fun setRecognizerBeepMuted(mute: Boolean): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        val audio = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false
        val direction = if (mute) AudioManager.ADJUST_MUTE else AudioManager.ADJUST_UNMUTE
        return try {
            audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, direction, 0)
            true
        } catch (e: SecurityException) {
            false
        }
    }
}
