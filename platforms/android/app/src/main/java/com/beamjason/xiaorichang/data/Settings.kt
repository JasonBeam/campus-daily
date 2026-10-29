package com.beamjason.xiaorichang.data

import com.beamjason.xiaorichang.core.WaterProfile
import com.beamjason.xiaorichang.net.*
import org.json.JSONObject

fun JSONObject.text(key: String): String = opt(key)?.takeUnless { it == JSONObject.NULL }?.toString().orEmpty()

data class WaterSettings(
    val secret: String = "", val sid: String = "", val studentId: String = "", val schoolId: String = "",
    val machineId: String = "", val bleName: String = "", val typeId: Int = -1, val version: Int = 1,
    val address: String? = null, val room: String = "", val access:WaterAccessSession? = null
) {
    val hasPlatform get() = (access?.let{runCatching{it.validate()}.isSuccess} == true || secret.isNotBlank() && sid.isNotBlank()) && bleName.isNotBlank() && typeId >= 0 && version > 0
    val configured get() = runCatching { profile().validate() }.isSuccess
    fun profile() = WaterProfile(secret, sid, studentId, schoolId, machineId.uppercase(), bleName, typeId, version,access=access)
    fun platform() = HotWaterProfile(secret, sid, bleName, typeId, version,access)
    fun json() = JSONObject().put("secret",secret).put("sid",sid).put("studentId",studentId).put("schoolId",schoolId)
        .put("machineId",machineId).put("bleName",bleName).put("typeId",typeId).put("version",version).put("address",address).put("room",room).put("access",access?.json())
    companion object {
        fun read(j: JSONObject) = WaterSettings(j.text("secret"),j.text("sid"),j.text("studentId").ifBlank { j.text("studentID") },
            j.text("schoolId").ifBlank { j.text("schoolID") },j.text("machineId").ifBlank { j.text("machineID") },j.text("bleName"),
            j.optInt("typeId",j.optInt("typeID",-1)),j.optInt("version",1),j.text("address").takeIf(String::isNotBlank),j.text("room"),j.optJSONObject("access")?.let{WaterAccessSession.read(it)})
    }
}

/** A saved address is only a hint: every connection still verifies hardware ID.
 * Preserve it only when the owner, school, selected machine and room all match. */
fun previouslyVerifiedAddress(water:WaterSettings,student:String,school:String,machine:String,room:String):String? =
    water.address?.takeIf { it.isNotBlank() && student.isNotBlank() && school.isNotBlank() && machine.isNotBlank() && room.isNotBlank() &&
        water.studentId==student && water.schoolId==school && water.machineId.equals(machine,ignoreCase=true) && water.room==room }

fun CampusConfig.json() = JSONObject().put("syscustid",syscustid).put("acc_token",token).put("areacode",areaCode)
    .put("custid",custid).put("timestamp",timestamp).put("userAgent",userAgent).put("dorm",dorm)
    .put("buildingID",buildingId).put("meterID",meterId).put("campusVersion",campusVersion).put("portal_dorm_address",portalDormAddress)
fun readCampus(j: JSONObject) = CampusConfig(j.text("syscustid"),j.text("acc_token").ifBlank { j.text("token") },
    j.text("areacode").ifBlank { j.text("areaCode") },j.text("custid"),j.text("timestamp"),j.text("userAgent"),
    j.text("dorm").ifBlank { j.text("dormRoom") },j.text("buildingID"),j.text("meterID"),j.text("campusVersion").ifBlank { "v1.1.55" },j.text("portal_dorm_address"))
fun UjingAccount.json() = JSONObject().put("id",id).put("businessUserId",businessUserId).put("token",token).put("clientId",clientId).put("userAgent",userAgent)
fun readAccount(j: JSONObject) = UjingAccount(j.getString("id"),j.getString("businessUserId"),j.getString("token"),j.getString("clientId"),j.getString("userAgent"))

data class SavedWasher(val id: String, val qr: String, val name: String, val number: String) {
    fun json() = JSONObject().put("id",id).put("qr",qr).put("name",name).put("number",number)
    companion object { fun read(j: JSONObject) = SavedWasher(j.getString("id"),j.getString("qr"),j.getString("name"),j.getString("number")) }
}

data class BalanceCache(val owner: String = "", val card: String? = null, val cardAt: Long = 0,
                        val power: PowerMeter? = null, val powerAt: Long = 0, val cardOwner:String = "") {
    fun json() = JSONObject().put("owner",owner).put("card",card).put("cardAt",cardAt).put("power",power?.json()).put("powerAt",powerAt).put("cardOwner",cardOwner)
    companion object {
        fun read(j: JSONObject) = BalanceCache(j.text("owner"),j.text("card").takeIf(String::isNotBlank),j.optLong("cardAt"),
            j.optJSONObject("power")?.let(PowerMeter::read),j.optLong("powerAt"),j.text("cardOwner"))
    }
}
