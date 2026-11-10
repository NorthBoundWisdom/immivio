package org.vrpassthroughplayer.plugin

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.PowerManager
import android.util.Log

/** Hardware proximity when exposed; display-off fallback. Never uses hands or window focus. */
internal class HeadsetPresenceMonitor(
    private val context: Context,
    private val changed: (Boolean, String) -> Unit,
) : SensorEventListener {
    private val manager = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
    private var registered = false
    private var sensor: Sensor? = null
    private val state = HeadsetPresenceState()
    private var closed = false
    private val receiver =
        object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    Intent.ACTION_SCREEN_OFF -> publish(state.screen(false), "screen_off")
                    Intent.ACTION_SCREEN_ON -> publish(state.screen(true), "screen_on")
                }
            }
        }

    fun start() {
        if (closed) return
        sensor = manager?.getDefaultSensor(Sensor.TYPE_PROXIMITY)
        sensor?.let {
            if (
                runCatching {
                        manager?.registerListener(this, it, SensorManager.SENSOR_DELAY_NORMAL)
                    }
                    .getOrDefault(false) != true
            )
                sensor = null
        }
        val filter =
            IntentFilter().apply {
                addAction(Intent.ACTION_SCREEN_OFF)
                addAction(Intent.ACTION_SCREEN_ON)
            }
        registered =
            runCatching {
                    if (Build.VERSION.SDK_INT >= 33)
                        context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    else context.registerReceiver(receiver, filter)
                    true
                }
                .onFailure { Log.w("QuestPlayer", "Screen presence fallback unavailable", it) }
                .getOrDefault(false)
        // Snapshot after registration: an already-off display need not emit another broadcast.
        val interactive =
            (context.getSystemService(Context.POWER_SERVICE) as? PowerManager)?.isInteractive
        if (interactive != null) publish(state.screen(interactive), "screen_initial")
        Log.i(
            "QuestPlayer",
            "Headset presence: proximity=${sensor != null}; screen_off_fallback=$registered",
        )
    }

    private fun publish(present: Boolean?, source: String) {
        if (closed || present == null) return
        Log.i("QuestPlayer", "Headset presence=$present source=$source")
        changed(present, source)
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (event.sensor.type != Sensor.TYPE_PROXIMITY || event.values.isEmpty()) return
        if (!event.values[0].isFinite() || event.values[0] < 0 || event.sensor.maximumRange <= 0)
            return
        publish(state.proximity(event.values[0] < event.sensor.maximumRange), "proximity")
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    fun close() {
        if (closed) return
        closed = true
        state.close()
        manager?.unregisterListener(this)
        if (registered) {
            runCatching { context.unregisterReceiver(receiver) }
            registered = false
        }
    }
}
