package com.beamjason.xiaorichang

import android.os.Bundle
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import com.beamjason.xiaorichang.ble.BleWaterTransport
import com.beamjason.xiaorichang.core.WaterProtocol
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.File

/** Developer acceptance on an authorized USB device. No account, HTTP client,
 * authorizations, valve commands, settlement or configuration mutation. The only
 * write permitted here is the existing single-byte hardware identity query. */
class BleReadOnlyActivity:ComponentActivity() {
    private lateinit var transport:BleWaterTransport
    override fun onCreate(savedInstanceState:Bundle?) {
        super.onCreate(savedInstanceState)
        val text=TextView(this).apply{setPadding(32,64,32,32);textSize=18f;text="正在进行蓝牙只读检查…"}
        setContentView(text)
        transport=BleWaterTransport(this)
        lifecycleScope.launch {
            val report=JSONObject().put("water_authorization_sent",false)
            try {
                val name=intent.getStringExtra("radio_name").orEmpty()
                val expected=intent.getStringExtra("machine_id").orEmpty()
                require(name.length in 1..64 && expected.matches(Regex("[0-9A-Fa-f]{8}")))
                val found=transport.scanCandidates(name)
                report.put("candidates",found.size)
                text.text="发现 ${found.size} 台目标水控，正在读取编号…"
                var matched=false
                val errors=org.json.JSONArray()
                for(candidate in found.take(8)) {
                    try {
                        transport.connect(name,candidate.address)
                        val actual=WaterProtocol.identity(transport.exchange(byteArrayOf(0xAA.toByte())))
                        if(actual.equals(expected,true)){matched=true;break}
                    } catch(e:Exception) {errors.put(e.javaClass.simpleName)}
                    finally {transport.disconnect()}
                }
                report.put("identity_matched",matched).put("errors",errors)
                text.text=if(matched)"已通过蓝牙读取并核对宿舍水控编号。\n已断开，没有申请用水授权。" else "未读到匹配的宿舍水控编号。\n发现 ${found.size} 台候选设备，没有申请用水授权。"
            } catch(e:Exception) {
                report.put("error_type",e.javaClass.simpleName)
                text.text="蓝牙只读检查未完成：${e.message}"
            } finally {
                transport.disconnect()
                File(noBackupFilesDir,"water-ble-acceptance.json").writeText(report.toString())
            }
        }
    }
    override fun onDestroy(){transport.disconnect();super.onDestroy()}
}
