package org.vrpassthroughplayer.plugin

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.util.Log

/** Real PICO library entry. The player still uses Godot's normal immersive Activity. */
class ImmivioLauncherActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.i("ImmivioLauncher", "Opening the immersive player")
        startActivity(Intent(Intent.ACTION_MAIN)
            .setClassName(packageName, "com.godot.game.GodotAppLauncher")
            .addCategory("org.khronos.openxr.intent.category.IMMERSIVE_HMD")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
        finish()
    }
}
