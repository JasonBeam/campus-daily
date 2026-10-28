package com.beamjason.xiaorichang.data

import org.json.JSONObject

/** Shared platform parameters only: provisioning must never bind a student's
 * account, room or controller on their behalf. The actual seed is not an APK asset. */
fun parseDevelopmentPlatform(text:String):WaterSettings {
    require(text.toByteArray().size<=8192){"平台配置大小不正确"}
    val value=JSONObject(text)
    val allowed=setOf("secret","sid","bleName","typeID","typeId","version")
    require(value.keys().asSequence().all{it in allowed}){"平台配置不能包含个人账号或水控信息"}
    require(listOf("secret","sid","bleName").all{value.opt(it) is String} && value.has("version") && (value.has("typeID")||value.has("typeId")))
    if(value.has("typeID")&&value.has("typeId"))require(value.getInt("typeID")==value.getInt("typeId"))
    val seed=WaterSettings.read(value)
    require(seed.hasPlatform && seed.secret.toByteArray().size<=256 && seed.sid.length<=128 && seed.bleName.length<=64
        && seed.typeId>=0 && seed.version>0
        && listOf(seed.sid,seed.bleName).none{it.any(Char::isISOControl)}){"平台接入参数不完整"}
    return seed
}
