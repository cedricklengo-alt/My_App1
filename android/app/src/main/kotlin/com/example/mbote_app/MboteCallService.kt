package com.example.mbote_app

import android.net.Uri
import android.os.Build
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.telecom.VideoProfile
import android.util.Log

/**
 * 📞 ConnectionService Telecom — rend chaque appel VoIP MboteCall visible
 * du système Android : historique d'appels, écran verrouillé, Android Auto,
 * routage Bluetooth. L'appel reste « self-managed » : le vrai média passe
 * par WebRTC (flutter_webrtc), Telecom ne gère que la signalisation UI.
 */
class MboteCallService : ConnectionService() {

    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection? {
        val extras = request?.extras
        val callId = extras?.getString("mbote_call_id") ?: ""
        val video = extras?.getBoolean("mbote_video") == true
        val conn = MboteConnection(callId, video).apply {
            connectionCapabilities = CAPABILITY_MUTE or CAPABILITY_SUPPORT_HOLD
            audioModeIsVoip = true
            // Appel entrant : état RINGING → l'UI Flutter (IncomingCallScreen)
            // répond via le canal, puis onActive()/onAnswer().
            setRinging()
            setInitialized()
        }
        connexions[callId] = conn
        Log.d(TAG, "Connexion entrante créée callId=$callId video=$video")
        return conn
    }

    override fun onCreateOutgoingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection? {
        val callId = request?.extras?.getString("mbote_call_id") ?: ""
        val video = request?.extras?.getBoolean("mbote_video") == true
        val conn = MboteConnection(callId, video).apply {
            audioModeIsVoip = true
            setDialing()
            setInitialized()
        }
        connexions[callId] = conn
        return conn
    }

    companion object {
        private const val TAG = "MboteCall"
        private val connexions = mutableMapOf<String, MboteConnection>()

        fun terminer(callId: String) {
            connexions.remove(callId)?.let {
                it.setDisconnected(DisconnectCause(DisconnectCause.LOCAL))
                it.destroy()
            }
        }

        fun aUnAppelActif(): Boolean = connexions.isNotEmpty()
    }
}

/** Connection concrète : relaie l'état vers le système sans jamais planter. */
private class MboteConnection(
    val callId: String,
    val video: Boolean
) : Connection() {
    override fun onShowIncomingCallUi() { /* l'UI Flutter affiche IncomingCallScreen via FCM/WS */ }
    override fun onAnswer() { setActiveSafely() }
    override fun onReject() { setDisconnectedSafely(DisconnectCause.REJECTED) }
    override fun onDisconnect() { setDisconnectedSafely(DisconnectCause.LOCAL) }
    override fun onHold() { setOnHoldSafely() }
    override fun onUnhold() { setActiveSafely() }
    override fun onStateChanged(state: Int) { Log.d("MboteCall", "callId=$callId état=$state") }

    private fun setActiveSafely() = try { setActive() } catch (e: Exception) { Log.e("MboteCall", "setActive KO", e) }
    private fun setOnHoldSafely() = try { setOnHold() } catch (e: Exception) { Log.e("MboteCall", "hold KO", e) }
    private fun setDisconnectedSafely(cause: DisconnectCause) =
        try { setDisconnected(cause); destroy() } catch (e: Exception) { Log.e("MboteCall", "disconnect KO", e) }
}
