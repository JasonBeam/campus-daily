package com.beamjason.xiaorichang.ble

import android.content.Context

/** Local debug stages/counts only: no advertising payloads, addresses, account
 * values, water frames or authorization data. */
internal class BleSupport(context:Context) {
    private val trace=WaterDiagnosticStore.trace(context)
    @Synchronized fun event(stage:String,numbers:Map<String,Int> = emptyMap()) {
        trace.ble(stage,numbers)
    }
}
