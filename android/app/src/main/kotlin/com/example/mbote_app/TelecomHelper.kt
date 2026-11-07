package com.example.mbote_app

import android.Manifest
import android.annotation.SuppressLint
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.telecom.CallAudioState
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Helper Telecom « self-managed » — enregistre l'appel VoIP MboteCall auprès
 * du framework Telecom Android (comme WhatsApp / Google Phone) :
 * historique d'appels système, écran verrouillé, Android Auto, Bluetooth.
 *
 * Nécessite la permission MANAGE_OWN_CALLS (demandée au runtime côté Flutter).
 */
object TelecomHelper {
    private const val TAG = "MboteCall"
    private const val ID_COMPTE = "mbotecall_compte"

    private fun handle(context: Context): PhoneAccountHandle {
        return PhoneAccountHandle(
            ComponentName(context, MboteCallService::class.java),
            ID_COMPTE
        )
    }

    /** Enregistre le PhoneAccount self-managed (idempotent). */
    @SuppressLint("MissingPermission")
    fun enregistrer(context: Context): Boolean {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.MANAGE_OWN_CALLS)
            != PackageManager.PERMISSION_GRANTED) {
            Log.w(TAG, "MANAGE_OWN_CALLS non accordée — Telecom ignoré")
            return false
        }
        val tm = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        val handle = handle(context)
        val account = PhoneAccount.builder(handle, "MboteCall")
            .setCapabilities(
                PhoneAccount.CAPABILITY_SELF_MANAGED or
                PhoneAccount.CAPABILITY_SUPPORTS_VIDEO_CALLING or
                PhoneAccount.CAPABILITY_VIDEO_CALLING
            )
            .build()
        tm.registerPhoneAccount(account)
        Log.d(TAG, "PhoneAccount self-managed enregistré")
        return true
    }

    /** Place un appel sortant dans le Telecom Framework. */
    @SuppressLint("MissingPermission")
    fun placeCall(context: Context, callId: String, nom: String, phone: String, video: Boolean): Boolean {
        if (!enregistrer(context)) return false
        val tm = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        val extras = android.os.Bundle().apply {
            putString("mbote_call_id", callId)
            putBoolean("mbote_video", video)
        }
        val request = ConnectionRequest.Builder()
            .setAddress(Uri.parse("tel:$phone"))
            .setExtras(extras)
            .setVideoState(if (video) ConnectionRequest.VIDEO_STATE_VIDEO_TX or ConnectionRequest.VIDEO_STATE_VIDEO_RX
                              else ConnectionRequest.VIDEO_STATE_AUDIO_ONLY)
            .build()
        return try {
            tm.placeCall(request, android.os.Bundle())
            MboteCallForegroundService.start(context, callId, nom.ifEmpty { phone }, video)
            true
        } catch (e: Exception) {
            Log.e(TAG, "placeCall KO", e)
            false
        }
    }

    /** Termine l'appel côté Telecom + arrête le service foreground. */
    fun endCall(context: Context, callId: String) {
        MboteCallService.terminer(callId)
    }

    fun hasActiveCall(): Boolean = MboteCallService.aUnAppelActif()
}
