package com.beamjason.xiaorichang.ble

import android.content.Context
import com.beamjason.xiaorichang.BuildConfig
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Local debug stages/counts only: no advertising payloads, addresses, account
 * values, water frames or authorization data. */
internal class BleSupport(context:Context) {
    private val file=File(context.noBackupFilesDir,"water-ble-support.json")
    private val events=JSONArray()
    @Synchronized fun event(stage:String,numbers:Map<String,Int> = emptyMap()) {
        if(!BuildConfig.DEBUG)return
        runCatching {
            val entry=JSONObject().put("stage",stage).put("time",System.currentTimeMillis())
            numbers.forEach{(key,value)->entry.put(key,value)}
            if(events.length()>=40)events.remove(0)
            events.put(entry)
            file.writeText(JSONObject().put("events",events).toString())
        }
    }
}
