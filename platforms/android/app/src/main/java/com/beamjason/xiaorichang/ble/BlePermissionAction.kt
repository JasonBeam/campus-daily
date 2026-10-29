package com.beamjason.xiaorichang.ble

/** A permission response only resumes the action while its original page is open. */
fun mayResumeBleAction(action:String,page:String):Boolean = when(action) {
    "start", "finish", "inspect" -> page=="water"
    "scan" -> page=="dorm"
    else -> false
}
