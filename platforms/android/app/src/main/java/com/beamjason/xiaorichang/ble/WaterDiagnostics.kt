package com.beamjason.xiaorichang.ble

import org.json.JSONArray
import org.json.JSONObject

/** A bounded allowlist of stages and counts; never accepts identities or frame bytes as text. */
class WaterDiagnostics(private val save:(String)->Unit={},history:String?=null) {
    enum class Event { START, REVIEW, FINISH, SESSION_SAVED, AUTHORIZATION_REPLY, STATE_REPLY, FINISH_BLOCKED, CLOSE, FAILED }
    private val rows=mutableListOf<JSONObject>()
    init {
        runCatching { JSONArray(history ?: "[]") }.getOrNull()?.let { input ->
            for(i in maxOf(0,input.length()-200) until input.length()) {
                val row=input.optJSONObject(i) ?: continue
                val event=row.optString("event")
                if(event !in Event.entries.map{it.name} && event !in BLE_EVENTS)continue
                val clean=JSONObject().put("event",event).put("time",row.optLong("time"))
                row.optString("stage").takeIf {it in ShowerStage.entries.map{stage->stage.name}}?.let{clean.put("stage",it)}
                for(key in NUMBERS)if(row.has(key))clean.put(key,row.optInt(key).coerceIn(-65536,65536))
                rows+=clean
            }
        }
    }
    @Synchronized fun record(event:Event,stage:ShowerStage?=null,frame:ByteArray?=null) {
        val row=JSONObject().put("event",event.name).put("time",System.currentTimeMillis())
        stage?.let{row.put("stage",it.name)}
        frame?.let{row.put("bytes",it.size.coerceAtMost(65536)).put("frameKind",frameKind(it))}
        append(row)
    }
    @Synchronized fun ble(event:String,numbers:Map<String,Int> = emptyMap()) {
        require(event in BLE_EVENTS)
        val row=JSONObject().put("event",event).put("time",System.currentTimeMillis())
        numbers.filterKeys{it in NUMBERS}.forEach{(k,v)->row.put(k,v.coerceIn(-65536,65536))}
        append(row)
    }
    private fun append(row:JSONObject) {
        rows+=row;while(rows.size>200)rows.removeAt(0)
        runCatching{save(JSONArray(rows).toString())}
    }
    @Synchronized fun snapshot()=JSONArray(rows.map{JSONObject(it.toString())})
    companion object {
        private val BLE_EVENTS=setOf("connect-start","connection-state","services","notifications","gatt-ready","connect-failed","scan-error","scan-start","scan-end","disconnect","write","reply","reuse-connection")
        private val NUMBERS=setOf("status","state","code","packets","matches","bytes","frameKind","command")
        fun frameKind(bytes:ByteArray)=when {
            bytes.size==20 && bytes[0]==0x55.toByte()->1
            bytes.size==9 && bytes[0]==0xAA.toByte()->2
            bytes.contentEquals(byteArrayOf(0xA5.toByte()))->3
            else->0
        }
    }
}
