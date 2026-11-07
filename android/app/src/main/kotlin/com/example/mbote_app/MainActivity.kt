package com.example.mbote_app

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioEffect
import android.media.AudioManager
import android.media.RingtoneManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Notification as AndroidNotification
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * PONT FLUTTER ↔ ANDROID — architecture Platform Channels de MboteCall.
 *
 * Canaux exposés (tous en requête → réponse typée, jamais d'exception nue) :
 *  - "mbote/liens"  : deep-links mbote://post/<id>        (méthodes: lienInitial, lien)
 *  - "mbote/appel"  : intégration Telecom/VoIP            (placeCall, terminerAppel, appelEnCours)
 *  - "mbote/audio"  : routing audio pro                   (modeAppel, hautParleur, bluetooth, ecouteur,
 *                                                            activerEffets, focusAudio)
 *
 * Règles : Result.error(code, message, details) côté natif ; try/catch + logs
 * tagués "MboteCall" partout ; aucune fuite de ressource (effets audio libérés).
 */
class MainActivity : FlutterActivity() {
    private var lienInitial: String? = null
    private var canalLiens: MethodChannel? = null

    // 🎚️ État audio pro (AEC/NS/AGC) — libéré à la fin de l'appel.
    private var aec: AcousticEchoCanceler? = null
    private var ns: NoiseSuppressor? = null
    private var agc: AutomaticGainControl? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        creerCanauxNotifications()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        lienInitial = lienDepuisIntent(intent)

        canalLiens = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mbote/liens")
        canalLiens?.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    // Remis une seule fois : une relance de l'app ne doit pas
                    // rouvrir la publication précédente.
                    "lienInitial" -> {
                        result.success(lienInitial)
                        lienInitial = null
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                Log.e(TAG, "mbote/liens ${call.method} KO", e)
                result.error("LIEN_KO", e.message, null)
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mbote/appel")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "placeCall" -> {
                            val args = call.arguments as? Map<*, *>
                            val ok = TelecomHelper.placeCall(
                                context = this,
                                callId = args?.get("call_id") as? String ?: "",
                                nom = args?.get("nom") as? String ?: "",
                                phone = args?.get("phone") as? String ?: "",
                                video = args?.get("video") as? Boolean ?: false,
                            )
                            result.success(mapOf("ok" to ok))
                        }
                        "terminerAppel" -> {
                            val args = call.arguments as? Map<*, *>
                            TelecomHelper.endCall(this, args?.get("call_id") as? String ?: "")
                            MboteCallForegroundService.stop(this)
                            result.success(mapOf("ok" to true))
                        }
                        "appelEnCours" -> result.success(mapOf("en_cours" to TelecomHelper.hasActiveCall()))
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "mbote/appel ${call.method} KO", e)
                    result.error("APPEL_KO", e.message, null)
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mbote/audio")
            .setMethodCallHandler { call, result ->
                try {
                    val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    when (call.method) {
                        "modeAppel" -> {
                            // MODE_IN_COMMUNICATION : comme WhatsApp, l'audio
                            // passe par l'écouteur, le HP reste off par défaut.
                            audio.mode = AudioManager.MODE_IN_COMMUNICATION
                            audio.isSpeakerphoneOn = false
                            audio.isBluetoothScoOn = false
                            result.success(mapOf("ok" to true))
                        }
                        "hautParleur" -> {
                            audio.isSpeakerphoneOn = (call.arguments as? Boolean) ?: false
                            result.success(mapOf("ok" to true))
                        }
                        "bluetooth" -> {
                            audio.isBluetoothScoOn = (call.arguments as? Boolean) ?: false
                            if ((call.arguments as? Boolean) == true) audio.startBluetoothSco()
                            result.success(mapOf("ok" to true))
                        }
                        "ecouteur" -> {
                            audio.isSpeakerphoneOn = false
                            audio.isBluetoothScoOn = false
                            result.success(mapOf("ok" to true))
                        }
                        "activerEffets" -> {
                            // AEC + NS + AGC quand le matériel les supporte.
                            val session = audio.generateAudioSessionId()
                            libererEffets()
                            if (session != 0 && AudioEffect.isEffectTypeSupported(AudioEffect.EFFECT_TYPE_AEC)) {
                                aec = AcousticEchoCanceler.create(session); aec?.enabled = true
                            }
                            if (session != 0 && NoiseSuppressor.isAvailable()) {
                                ns = NoiseSuppressor.create(session); ns?.enabled = true
                            }
                            if (session != 0 && AutomaticGainControl.isAvailable()) {
                                agc = AutomaticGainControl.create(session); agc?.enabled = true
                            }
                            Log.d(TAG, "Effets audio: aec=${aec != null} ns=${ns != null} agc=${agc != null}")
                            result.success(mapOf("aec" to (aec != null), "ns" to (ns != null), "agc" to (agc != null)))
                        }
                        "libererEffets" -> { libererEffets(); result.success(mapOf("ok" to true)) }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "mbote/audio ${call.method} KO", e)
                    result.error("AUDIO_KO", e.message, null)
                }
            }
    }

    private fun libererEffets() {
        try { aec?.release(); aec = null } catch (_: Exception) {}
        try { ns?.release(); ns = null } catch (_: Exception) {}
        try { agc?.release(); agc = null } catch (_: Exception) {}
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val lien = lienDepuisIntent(intent)
        if (lien != null) canalLiens?.invokeMethod("lien", lien)
    }

    override fun onDestroy() {
        libererEffets()
        super.onDestroy()
    }

    private fun lienDepuisIntent(intent: Intent?): String? {
        val data = intent?.data ?: return null
        if (data.scheme != "mbote" || data.host != "post") return null
        val id = data.pathSegments.firstOrNull() ?: return null
        return "mbote://post/$id"
    }

    /**
     * 🔔 Canaux de notification (Android 8+) — créés UNE FOIS au démarrage :
     * une notification postée vers un canal inexistant est SILENCIEUSEMENT
     * jetée par le système.
     */
    private fun creerCanauxNotifications() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val gestionnaire = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        fun canal(id: String, nom: String, importance: Int, description: String,
                  sonnerie: Boolean, vibration: Boolean, pattern: LongArray?,
                  lockscreen: Int, bypassDnd: Boolean): NotificationChannel {
            return NotificationChannel(id, nom, importance).apply {
                this.description = description
                enableVibration(vibration)
                vibrationPattern = pattern
                val type = if (sonnerie) RingtoneManager.TYPE_RINGTONE else RingtoneManager.TYPE_NOTIFICATION
                setSound(RingtoneManager.getDefaultUri(type),
                    AudioAttributes.Builder()
                        .setUsage(if (sonnerie) AudioAttributes.USAGE_NOTIFICATION_RINGTONE
                                  else AudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_INSTANT)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build())
                lockscreenVisibility = lockscreen
                setBypassDnd(bypassDnd)
            }
        }

        val appels = canal("mbote_calls", "Appels entrants", NotificationManager.IMPORTANCE_MAX,
            "Appels MboteCall (sonnerie même écran verrouillé)", sonnerie = true, vibration = true,
            pattern = longArrayOf(0, 600, 400, 600, 400, 600),
            lockscreen = AndroidNotification.VISIBILITY_PUBLIC, bypassDnd = true)
        val messages = canal("mbote_messages", "Messages et interactions", NotificationManager.IMPORTANCE_HIGH,
            "Likes, commentaires, messages, appels manqués", sonnerie = false, vibration = true,
            pattern = null, lockscreen = AndroidNotification.VISIBILITY_PRIVATE, bypassDnd = false)
        val systeme = canal("mbote_systeme", "Système et sécurité", NotificationManager.IMPORTANCE_DEFAULT,
            "Compte, sécurité, mises à jour", sonnerie = false, vibration = false,
            pattern = null, lockscreen = AndroidNotification.VISIBILITY_PRIVATE, bypassDnd = false)
        val telechargements = canal("mbote_telechargements", "Téléchargements", NotificationManager.IMPORTANCE_LOW,
            "Progression des envois de médias", sonnerie = false, vibration = false,
            pattern = null, lockscreen = AndroidNotification.VISIBILITY_PRIVATE, bypassDnd = false)

        gestionnaire.createNotificationChannels(listOf(appels, messages, systeme, telechargements))
        Log.d(TAG, "Canaux de notification prêts (${Build.VERSION.SDK_INT})")
    }

    companion object {
        private const val TAG = "MboteCall"
    }
}
