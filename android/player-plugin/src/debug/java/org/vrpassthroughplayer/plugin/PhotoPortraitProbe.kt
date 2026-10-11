package org.vrpassthroughplayer.plugin

import android.content.Context
import org.json.JSONObject
import java.io.File
import java.util.concurrent.atomic.AtomicInteger

/** A shell-only public fixture check. Does not change the displayed photo, layout or history. */
internal object PhotoPortraitProbe {
    private val sequence = AtomicInteger(500000)
    @Volatile private var active: PhotoBridge? = null
    fun request(context: Context, key: String): Int {
        require(key.matches(Regex("[A-Za-z0-9_-]{1,64}")))
        val fixture = File(context.filesDir,"fixtures/photo-portrait-test.png")
        require(fixture.isFile && fixture.length() in 1..10_000_000)
        check(active == null) { "Photo portrait probe already running" }
        val id = sequence.incrementAndGet()
        val directory = File(context.filesDir,"diagnostics").apply { mkdirs() }
        val reportFile = File(directory,"photo_portrait_$key.json")
        val base = JSONObject().put("request",key).put("id",id).put("state","running")
            .put("scope","Production Bitmap/EXIF, photo depth, RVM OpenCL and matching stereo mask; not XR interaction or quality acceptance")
        fun save(report: JSONObject) {
            val tmp = File(directory,"photo-portrait-$key.tmp")
            tmp.writeText(report.toString()); require(tmp.renameTo(reportFile))
        }
        save(base)
        lateinit var bridge: PhotoBridge
        bridge = PhotoBridge({ context.applicationContext }, { it }, {}, "photo-portrait-probe") { name,_,json ->
            val result = JSONObject(json)
            try {
                when {
                    result.optString("state") == "error" -> error(result.optString("error"))
                    name == "photo_ready" && result.optString("state") == "ready" -> {
                        check(bridge.depth(id,1f,true)); save(JSONObject(base.toString()).put("phase","depth"))
                    }
                    name == "photo_depth" && result.optString("state") == "ready" -> {
                        check(bridge.portrait(id,id,1f)); save(JSONObject(base.toString()).put("phase","portrait"))
                    }
                    name == "photo_portrait" && result.optString("state") == "ready" -> {
                        val w = result.getInt("width"); val h = result.getInt("height")
                        val mask = File(result.getString("path")).readBytes(); require(mask.size == w*h && w%2 == 0)
                        val nonzero = mask.count { (it.toInt() and 255)>32 }
                        val clear = mask.count { (it.toInt() and 255)<8 }
                        var different = 0
                        for (y in 0 until h) for (x in 0 until w/2) if (mask[y*w+x] != mask[y*w+x+w/2]) different++
                        require(nonzero>0 && clear>0 && different>0) { "Portrait lacks foreground, clear background or stereo disparity" }
                        File(directory,"photo_portrait_$key.r8").writeBytes(mask)
                        save(JSONObject(base.toString()).put("state","passed").put("width",w).put("height",h)
                            .put("foreground_pixels",nonzero).put("clear_pixels",clear).put("different_eye_pixels",different)
                            .put("portrait_ms",result.optDouble("total_ms")))
                        bridge.close(); active = null
                    }
                }
            } catch (error: Throwable) {
                save(JSONObject(base.toString()).put("state","failed").put("error",error.javaClass.simpleName).put("reason",error.message))
                bridge.close(); active = null
            }
        }
        active = bridge
        require(bridge.open(id,"file://${fixture.absolutePath}"))
        return id
    }
}
