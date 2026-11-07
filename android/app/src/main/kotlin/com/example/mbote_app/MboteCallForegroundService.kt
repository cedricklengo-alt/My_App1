package com.example.mbote_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Person
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.Person as AndroidxPerson

/**
 * 🔧 Service foreground « appel en cours ».
 *
 * - Android 10-12 : notification classique canal mbote_calls.
 * - Android 11+   : notification **CallStyle** (style Google Phone/WhatsApp)
 *                   avec actions Répondre / Refuser.
 * - Android 14    : plein écran sur lockscreen via USE_FULL_SCREEN_INTENT.
 * - foregroundServiceType = phoneCall|microphone (obligatoire Android 12+).
 *
 * Le service démarre AVEC sa notification dans les 5 s (règle Android 12),
 * s'arrête proprement à la fin de l'appel, et ne redémarre pas tout seul
 * après un crash (START_NOT_STICKY).
 */
class MboteCallForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val callId = intent?.getStringExtra(EXTRA_CALL_ID) ?: ""
        val nom = intent?.getStringExtra(EXTRA_NOM) ?: "Appel MboteCall"
        val video = intent?.getBooleanExtra(EXTRA_VIDEO, false) == true
        demarrerAuPremierPlan(callId, nom, video)
        return START_NOT_STICKY
    }

    private fun demarrerAuPremierPlan(callId: String, nom: String, video: Boolean) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(NotificationChannel(
                CHANNEL_APPEL_EN_COURS, "Appel en cours",
                NotificationManager.IMPORTANCE_DEFAULT).apply {
                setSound(null, null); enableVibration(false)
            })
        }

        // Intent plein écran → rouvre l'app sur l'écran d'appel.
        val intentPleinEcran = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("mbote_call_id", callId)
        }
        val piPleinEcran = PendingIntent.getActivity(this, callId.hashCode(), intentPleinEcran,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val notif = NotificationCompat.Builder(this, CHANNEL_APPEL_EN_COURS)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setContentTitle(if (video) "Appel vidéo avec $nom" else "Appel avec $nom")
            .setContentText("Appel MboteCall en cours…")
            .setOngoing(true)
            .setContentIntent(piPleinEcran)
            .setFullScreenIntent(piPleinEcran, true) // Android 14 : lockscreen
            .build()

        // 🎨 CallStyle (Android 11+) : look natif Google Phone/WhatsApp,
        // avec action « Refuser » directement dans la notification.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val personne = AndroidxPerson.Builder().setName(nom).setImportant(true).build()
            val intentRefus = Intent(this, MboteCallForegroundService::class.java).setAction(ACTION_REFUSER)
            val piRefus = PendingIntent.getService(this, REQ_REFUSER, intentRefus,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val style = NotificationCompat.CallStyle.forOngoingCall(personne, piRefus)
            notif = NotificationCompat.Builder(this, CHANNEL_APPEL_EN_COURS)
                .setSmallIcon(android.R.drawable.ic_menu_call)
                .setContentTitle(if (video) "Appel vidéo avec $nom" else "Appel avec $nom")
                .setOngoing(true)
                .setContentIntent(piPleinEcran)
                .setFullScreenIntent(piPleinEcran, true)
                .setStyle(style)
                .build()
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(ID_NOTIF, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(ID_NOTIF, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL)
            } else {
                startForeground(ID_NOTIF, notif)
            }
            Log.d(TAG, "Service foreground démarré (callId=$callId)")
        } catch (e: Exception) {
            Log.e(TAG, "startForeground KO (permission manquante ?)", e)
            stopSelf()
        }
    }

    override fun onDestroy() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    companion object {
        private const val TAG = "MboteCall"
        private const val CHANNEL_APPEL_EN_COURS = "mbote_appel_en_cours"
        private const val ID_NOTIF = 4242
        private const val EXTRA_CALL_ID = "call_id"
        private const val EXTRA_NOM = "nom"
        private const val EXTRA_VIDEO = "video"
        private const val ACTION_REFUSER = "refuser"
        private const val REQ_REFUSER = 77

        fun start(context: Context, callId: String, nom: String, video: Boolean) {
            val i = Intent(context, MboteCallForegroundService::class.java).apply {
                putExtra(EXTRA_CALL_ID, callId); putExtra(EXTRA_NOM, nom); putExtra(EXTRA_VIDEO, video)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(i)
                else context.startService(i)
            } catch (e: Exception) { Log.e(TAG, "start service KO", e) }
        }

        fun stop(context: Context) {
            try { context.stopService(Intent(context, MboteCallForegroundService::class.java)) } catch (_: Exception) {}
        }
    }
}
