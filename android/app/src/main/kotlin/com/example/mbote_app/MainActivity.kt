package com.example.mbote_app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * RÉCEPTION DES LIENS mbote://post/<id>
 *
 * Une publication partagée porte un lien public. Sur la page, le bouton
 * « Ouvrir dans MboteCall » déclenche ce schéma : sans ce code, le bouton
 * resterait sans effet. L'identifiant est transmis à Flutter, qui ouvre la
 * publication.
 */
class MainActivity : FlutterActivity() {
    private var lienInitial: String? = null
    private var canal: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        lienInitial = lienDepuisIntent(intent)
        canal = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mbote/liens")
        canal?.setMethodCallHandler { call, result ->
            if (call.method == "lienInitial") {
                // Remis une seule fois : une relance de l'app ne doit pas
                // rouvrir la publication précédente.
                result.success(lienInitial)
                lienInitial = null
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val lien = lienDepuisIntent(intent)
        if (lien != null) canal?.invokeMethod("lien", lien)
    }

    /** mbote://post/abc -> "post/abc" ; tout autre schéma est ignoré. */
    private fun lienDepuisIntent(intent: Intent?): String? {
        val uri = intent?.data ?: return null
        if (uri.scheme != "mbote") return null
        if (uri.host != "post") return null
        val id = uri.lastPathSegment ?: return null
        if (id.isEmpty()) return null
        return "post/$id"
    }
}
