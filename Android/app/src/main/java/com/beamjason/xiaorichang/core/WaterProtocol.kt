package com.beamjason.xiaorichang.core

import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Locale

data class WaterProfile(
    val secret: String, val sid: String, val studentId: String, val schoolId: String,
    val machineId: String, val bleName: String, val typeId: Int, val version: Int,
    val baseUrl: String = "https://isv.lxt6.cn",
    val access: com.beamjason.xiaorichang.net.WaterAccessSession? = null
) {
    fun validate() {
        require(baseUrl == "https://isv.lxt6.cn")
        if(access!=null){access.validate();require(access.studentId==studentId && access.schoolId==schoolId)}
        else {require(secret.isNotBlank() && secret.toByteArray().size <= 256);require(sid.isNotBlank() && sid.length <= 128)}
        require(studentId.matches(Regex("[A-Za-z0-9.-]{1,64}")))
        require(schoolId.matches(Regex("[A-Za-z0-9.-]{1,64}")))
        require(machineId.hexBytes()?.size == 4)
        require(bleName.isNotBlank() && bleName.length <= 64 && typeId >= 0 && version > 0)
    }
}

object WaterProtocol {
    const val SERVICE = "FFE0"
    const val NOTIFY = "FFE1"
    const val WRITE = "FFE2"

    fun decodeHex(input: String): ByteArray? {
        if (input.isEmpty() || input.length % 2 != 0 || !input.matches(Regex("[0-9A-Fa-f]+"))) return null
        return ByteArray(input.length / 2) { i -> input.substring(i * 2, i * 2 + 2).toInt(16).toByte() }
    }

    fun identity(frame: ByteArray): String {
        check(!frame.contentEquals(byteArrayOf(0xA5.toByte()))) { "水控正在使用，请先核对当前用水记录" }
        require(frame.size == 20 && frame[0] == 0x55.toByte()) { "水控返回的数据格式异常" }
        return frame.copyOfRange(1, 5).hex()
    }

    fun encodeForm(value: String): String = buildString {
        for (b in value.toByteArray(Charsets.UTF_8)) {
            val n = b.toInt() and 0xff
            when (n) {
                in 65..90, in 97..122, in 48..57, 45, 46, 95, 42 -> append(n.toChar())
                32 -> append('+')
                else -> append("%" + String.format(Locale.ROOT, "%02X", n))
            }
        }
    }

    fun signature(secret: String, wxcode: String): String =
        MessageDigest.getInstance("MD5").digest((secret + encodeForm(wxcode)).toByteArray(Charsets.UTF_8)).hex(lower = true)

    fun wxcode(profile: WaterProfile, frame: ByteArray, random: String): String {
        profile.validate()
        require(identity(frame) == profile.machineId.uppercase(Locale.ROOT)) { "wrong device" }
        require(random.matches(Regex("[0-9A-Z]{6}")))
        return listOf(
            "studentId=${profile.studentId}", "schoolId=${profile.schoolId}",
            "machineid=${profile.machineId.uppercase(Locale.ROOT)}", "machinedata=${frame.hex()}",
            "typeId=${profile.typeId}", "alleywaytype=0", "rand=$random", "version=${profile.version}"
        ).joinToString("*_")
    }

    fun closeCommand(authorizationId: String): ByteArray {
        val id = decodeHex(authorizationId)?.takeIf { it.size == 4 } ?: error("invalid authorization id")
        return byteArrayOf(0xAC.toByte()) + id.map { (it.toInt() xor 0x55).toByte() }.toByteArray()
    }
}

private fun ByteArray.hex(lower: Boolean = false): String {
    val alphabet = if (lower) "0123456789abcdef" else "0123456789ABCDEF"
    return buildString(size * 2) { for (b in this@hex) { val n=b.toInt() and 255; append(alphabet[n shr 4]); append(alphabet[n and 15]) } }
}

private fun String.hexBytes(): ByteArray? = WaterProtocol.decodeHex(this)

class FrameDecoder {
    private val pending = ArrayList<Byte>(64)
    fun append(chunk: ByteArray): List<ByteArray> {
        require(pending.size + chunk.size <= 256) { "frame buffer limit" }
        chunk.forEach(pending::add)
        val result = mutableListOf<ByteArray>()
        while (pending.isNotEmpty()) {
            val n = when (pending[0].toInt() and 0xff) { 0x55 -> 20; 0xAA -> 9; 0xA5 -> 1; else -> error("unknown frame") }
            if (pending.size < n) break
            result += ByteArray(n) { pending.removeAt(0) }
        }
        return result
    }
    val hasPartialFrame: Boolean get() = pending.isNotEmpty()
}

fun secureRandomWaterSuffix(): String {
    val alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    val random = SecureRandom()
    return buildString { repeat(6) { append(alphabet[random.nextInt(alphabet.length)]) } }
}
