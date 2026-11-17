package com.beamjason.xiaorichang.ble

import android.content.Context
import com.beamjason.xiaorichang.BuildConfig
import com.beamjason.xiaorichang.security.SecureStore
import org.json.JSONArray
import org.json.JSONObject

/** Private RX bytes; never included in the normal redacted diagnostic export. */
object WaterPassiveCapture {
    fun report(context:Context):String {
        check(BuildConfig.WATER_PASSIVE_DIAGNOSTICS)
        return SecureStore(context).get("water.passive-bluetooth.v1")?.toString(Charsets.UTF_8)
            ?: error("尚未收到蓝牙通知，请完成现场操作后再导出")
    }
    @Synchronized fun receive(context:Context,bytes:ByteArray,awaitingReply:Boolean) {
        if(!BuildConfig.WATER_PASSIVE_DIAGNOSTICS || bytes.isEmpty() || bytes.size>256)return
        runCatching {
            val secure=SecureStore(context)
            val stored=secure.get("water.passive-bluetooth.v1")?.takeIf { it.size<=65536 }
            val history=stored?.let { JSONArray(it.toString(Charsets.UTF_8)) } ?: JSONArray()
            val next=JSONArray()
            for(i in maxOf(0,history.length()-63) until history.length())next.put(history.get(i))
            next.put(JSONObject().put("receivedAt",System.currentTimeMillis()).put("awaitingReply",awaitingReply)
                .put("hex",bytes.joinToString(""){"%02X".format(it)}))
            secure.put("water.passive-bluetooth.v1",next.toString().toByteArray())
        } // Diagnostics never change a transaction result if local storage fails.
    }
}
