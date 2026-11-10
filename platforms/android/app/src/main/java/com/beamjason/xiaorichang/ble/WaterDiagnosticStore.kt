package com.beamjason.xiaorichang.ble

import android.content.Context
import android.os.Build
import android.util.AtomicFile
import com.beamjason.xiaorichang.BuildConfig
import org.json.JSONObject
import java.io.File

object WaterDiagnosticStore {
    private val traces=mutableMapOf<String,WaterDiagnostics>()
    @Synchronized fun trace(context:Context):WaterDiagnostics {
        val path=File(context.noBackupFilesDir,"water-diagnostics-v1.json")
        return traces.getOrPut(path.absolutePath) {
            val atomic=AtomicFile(path)
            val history=runCatching{atomic.openRead().use{it.readBytes().takeIf{bytes->bytes.size<=131072}?.toString(Charsets.UTF_8)}}.getOrNull()
            WaterDiagnostics(save={text->
                val stream=atomic.startWrite()
                try{stream.write(text.toByteArray());atomic.finishWrite(stream)}catch(e:Exception){atomic.failWrite(stream);throw e}
            },history=history)
        }
    }
    fun report(context:Context,session:ShowerSession?):String = JSONObject()
        .put("schema",1).put("generatedAt",System.currentTimeMillis())
        .put("appVersion",BuildConfig.VERSION_NAME).put("build",BuildConfig.VERSION_CODE)
        .put("deviceModel",Build.MODEL).put("systemVersion",Build.VERSION.RELEASE)
        .put("sessionStage",session?.stage?.name).put("stateReviewRequired",session?.stateReviewRequired==true)
        .put("events",trace(context).snapshot()).toString(2)
}
