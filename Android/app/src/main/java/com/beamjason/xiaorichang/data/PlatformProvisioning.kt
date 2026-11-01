package com.beamjason.xiaorichang.data

import org.json.JSONObject

/** Shared platform parameters only; never a student's account, room or controller. */
fun parseDevelopmentPlatform(text:String):WaterSettings {
    require(text.toByteArray().size<=8192){"平台配置大小不正确"}
    val value=JSONObject(text)
    val allowed=setOf("secret","sid","bleName","typeID","typeId","version")
    require(value.keys().asSequence().all{it in allowed}){"平台配置不能包含个人账号或水控信息"}
    require(listOf("secret","sid","bleName").all{value.opt(it) is String} && value.has("version") && (value.has("typeID")||value.has("typeId")))
    if(value.has("typeID")&&value.has("typeId"))require(value.getInt("typeID")==value.getInt("typeId"))
    for(key in listOf("version","typeID","typeId").filter{value.has(it)}) {
        val number=value.get(key)
        require((number is Int || number is Long) && (number as Number).toLong() in 0..Int.MAX_VALUE.toLong()) {"协议字段必须是有效整数"}
    }
    val seed=WaterSettings.read(value)
    require(seed.hasPlatform && seed.secret.toByteArray().size<=256 && seed.sid.length<=128 && seed.bleName.length<=64
        && seed.typeId>=0 && seed.version>0
        && listOf(seed.secret,seed.sid,seed.bleName).none{it.any(Char::isISOControl)}){"平台接入参数不完整"}
    return seed
}

/** User-selected platform-only handoff. No USB, DEBUG flag or previous identity required. */
fun parseWaterPlatformImport(text:String):WaterSettings {
    val value=JSONObject(text)
    require(value.keys().asSequence().toSet()==setOf("secret","sid","bleName","typeID","version")){"请选择不含个人账号、宿舍和设备信息的热水接入文件"}
    return parseDevelopmentPlatform(text)
}

fun loadBundledWaterPlatform(application:android.app.Application):WaterSettings? = runCatching {
    application.assets.open("CampusWaterPlatform.json").use {stream ->
        val bytes=java.io.ByteArrayOutputStream()
        val buffer=ByteArray(1024)
        while(true) {
            val n=stream.read(buffer);if(n<0)break
            require(bytes.size()+n<=8192)
            bytes.write(buffer,0,n)
        }
        parseWaterPlatformImport(bytes.toString("UTF-8"))
    }
}.getOrNull()

fun migrateWaterToDirect(previous:WaterSettings,platform:WaterSettings,identity:com.beamjason.xiaorichang.net.DormIdentity,
    owner:String,unresolved:Boolean):WaterSettings {
    check(!unresolved){"请先完成或核对当前热水会话"}
    require(platform.hasPlatform && platform.access==null)
    val access=previous.access ?: error("仅迁移旧版在线配置")
    previous.profile().validate()
    require(access.campusOwner==owner && previous.studentId==identity.studentId && previous.schoolId==identity.schoolId)
    return previous.copy(secret=platform.secret,sid=platform.sid,bleName=platform.bleName,typeId=platform.typeId,version=platform.version,access=null)
}
