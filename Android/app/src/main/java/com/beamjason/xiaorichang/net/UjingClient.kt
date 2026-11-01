package com.beamjason.xiaorichang.net

import android.net.Uri
import android.os.Build

import org.json.JSONObject
import javax.net.ssl.HttpsURLConnection
import java.net.URI
import java.net.URL
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class UjingAccount(val id: String, val businessUserId: String, val token: String,
                        val clientId: String, val userAgent: String) {
    fun headers() = mapOf("Authorization" to "Bearer $token", "x-app-code" to "BI",
        "x-app-version" to "2.4.18", "x-mobile-id" to clientId,
        "x-mobile-brand" to "android", "User-Agent" to userAgent)
}

data class WasherProgram(val id: Int, val name: String, val minutes: Int, val priceFen: Int)
data class WasherSnapshot(val id: String, val number: String, val title: String, val store: String,
                          val state: Int, val createEnabled: Boolean, val programs: List<WasherProgram>,
                          val storeId:String = "",val deviceTypeId:Int = -1,val activeOrderId:String? = null,val fetchedAt:Long = System.currentTimeMillis()) {
    val available get() = state==0 && createEnabled && activeOrderId==null
    val label get() = when(state) { 1 -> "洗衣中"; 11 -> "已被预约"; 2 -> "设备故障"; 8 -> "设备离线"; 7 -> "尚未开通"; 9 -> "设备停用"; else -> if(activeOrderId!=null) "已有订单" else if(available) "空闲" else "暂不可用" }
}

class UjingClient(private val userAgent: String = "CampusDaily/0.2.0 (Android ${Build.VERSION.RELEASE})") : LaundryApi {
    val clientId: String = UUID.randomUUID().toString()

    suspend fun sendCode(mobile: String) = withContext(Dispatchers.IO) {
        require(mobile.matches(Regex("1[0-9]{10}"))) { "请输入正确的 11 位手机号" }
        val query = Uri.Builder().appendQueryParameter("mobile", mobile).appendQueryParameter("type", "1").build().encodedQuery
        val root = request("/api/v1/captcha?$query", "GET", null, loginHeaders())
        require(root.optInt("code", -1) == 0) { "U净未接受验证码请求，请稍后重试" }
    }

    suspend fun login(mobile: String, code: String): UjingAccount = withContext(Dispatchers.IO) {
        require(mobile.matches(Regex("1[0-9]{10}"))) { "请输入正确的 11 位手机号" }
        require(code.matches(Regex("[0-9]{4,8}"))) { "请输入收到的验证码" }
        val body = JSONObject().put("mobile", mobile).put("captcha", code).toString().toByteArray()
        val root = request("/api/v1/login", "POST", body, loginHeaders())
        require(root.optInt("code", -1) == 0) { "U净未接受登录，请核对验证码" }
        val data = root.optJSONObject("data") ?: error("U净登录响应无效")
        require(!data.optBoolean("isTempToken", true)) { "U净要求额外验证，请先在官方客户端完成验证" }
        val token = data.optString("token")
        val id = data.optString("id")
        val business = data.optString("userId")
        require(token.length in 21..4096 && id.matches(Regex("[0-9]{1,32}")) && business.matches(Regex("[0-9]{1,32}")))
        val claims = jwtClaims(token)
        require(claims.optString("appUserId") == id) { "U净账号标识不匹配" }
        UjingAccount(id, business, token, clientId, userAgent)
    }

    suspend fun discoverAndRead(account: UjingAccount, qr: String): WasherSnapshot = withContext(Dispatchers.IO) {
        validateQr(qr)
        val headers = account.headers()
        val scan = request("/api/v1/devices/scanWasherCode", "POST",
            JSONObject().put("qrCode", qr).toString().toByteArray(), headers).optJSONObject("data")
            ?.optJSONObject("result") ?: error("U净未返回机器信息")
        val id = scan.optString("deviceId")
        require(id.isNotBlank() && scan.optInt("moduleType", -1) == 7) { "暂不支持这类洗衣机" }
        val info = request("/api/v1/app/washer/devices/program/info?deviceId=${Uri.encode(id)}", "GET", null, headers)
            .optJSONObject("data") ?: error("U净未返回洗衣程序")
        require(info.optString("deviceId") == id && info.optInt("moduleType", -2) == scan.optInt("moduleType"))
        val arr = info.optJSONArray("deviceWashModel") ?: error("洗衣程序为空")
        val programs = (0 until arr.length()).mapNotNull { i ->
            val p = arr.optJSONObject(i) ?: return@mapNotNull null
            if (p.optInt("hide", 0) != 0) return@mapNotNull null
            val price = if (p.optInt("isPromotion", 0) == 1) p.optInt("promotionPrice", -1) else p.optInt("basePrice", -1)
            val minutes = p.optInt("time", 0)
            require(price >= 0 && minutes > 0)
            WasherProgram(p.optInt("workModelId"), p.optString("workModelName"), minutes, price)
        }
        require(programs.isNotEmpty() && programs.map { it.id }.toSet().size == programs.size)
        WasherSnapshot(id, info.optString("deviceNo"), info.optString("deviceTypeName"),
            info.optString("storeName"), scan.optInt("status", -1), scan.optBoolean("createOrderEnabled"), programs,
            info.optString("storeId"),info.optInt("deviceTypeId",-1),scan.optString("orderId").takeUnless { it.isBlank() || it=="0" || it=="null" })
    }

    override suspend fun create(account:UjingAccount,snapshot:WasherSnapshot,program:WasherProgram):String = withContext(Dispatchers.IO) {
        require(snapshot.available && System.currentTimeMillis()-snapshot.fetchedAt in 0..59_999 && snapshot.storeId.isNotBlank() && snapshot.deviceTypeId>=0 && snapshot.programs.contains(program)) { "设备状态或价格已变化，请刷新后重试" }
        val data=request("/api/v1/orders/create","POST",JSONObject().put("type",1).put("deviceTypeId",snapshot.deviceTypeId)
            .put("deviceId",snapshot.id).put("deviceWashModelId",program.id).put("storeId",snapshot.storeId).put("additionParams",JSONObject()).toString().toByteArray(),account.headers()).opt("data")
        val id=if(data is JSONObject) data.optString("orderId",data.optString("id")) else data?.toString().orEmpty()
        require(validOrderId(id)) { "下单结果尚未确认，请勿重复下单" }; id
    }
    override suspend fun order(account:UjingAccount,id:String):LaundryOrder = withContext(Dispatchers.IO) {
        require(validOrderId(id)); LaundryOrder.read(request("/api/v1/orders/$id/detail?additional=price","GET",null,account.headers()).getJSONObject("data"))
    }
    override suspend fun payment(account:UjingAccount,id:String):JSONObject = withContext(Dispatchers.IO) {
        require(validOrderId(id))
        val data=request("/api/v1/payment/methods?orderId=$id&include=alipay","GET",null,account.headers()).getJSONObject("data")
        val arr=data.getJSONArray("channels"); val channels=(0 until arr.length()).map { arr.getJSONObject(it) }
        val selected=channels.firstOrNull { it.optString("channel")=="alipay" } ?: channels.firstOrNull { it.optString("channel")=="alipayF2F" } ?: error("该订单暂未提供支付宝付款方式")
        val channel=selected.getString("channel")
        val path=buildString {
            append("/api/v1/payment/arguments?channel=$channel&orderId=$id&payVersion=1")
            if(selected.has("branchType")) append("&branchType=${selected.getInt("branchType")}")
            if(channel=="alipayF2F") append("&alipayF2FNoAds=true")
        }
        request(path,"GET",null,account.headers()).getJSONObject("data")
    }
    override suspend fun cancel(account:UjingAccount,id:String) = withContext(Dispatchers.IO) {
        require(validOrderId(id)); request("/api/v1/orders/$id/cancel","POST",JSONObject().put("orderId",id).toString().toByteArray(),account.headers()); Unit
    }

    private fun loginHeaders() = mapOf("x-app-code" to "ZI", "x-app-version" to "2.4.18",
        "x-mobile-id" to clientId, "x-mobile-brand" to "android", "User-Agent" to userAgent)

    private fun request(path: String, method: String, body: ByteArray?, headers: Map<String, String>): JSONObject {
        require(path.startsWith("/api/v1/") && !path.startsWith("//"))
        require(headers.values.all { it.length<=8192 && it.none(Char::isISOControl) })
        val route=path.substringBefore('?')
        require(route in setOf("/api/v1/captcha","/api/v1/login","/api/v1/devices/scanWasherCode","/api/v1/app/washer/devices/program/info","/api/v1/orders/create","/api/v1/payment/methods","/api/v1/payment/arguments") || route.matches(Regex("/api/v1/orders/[A-Za-z0-9]{1,80}/(detail|cancel)")))
        val url = URL("https://phoenix.ujing.online$path")
        require(url.protocol == "https" && url.host == "phoenix.ujing.online" && url.port == -1)
        val connection = (url.openConnection() as HttpsURLConnection).apply {
            instanceFollowRedirects = false
            connectTimeout = 15_000; readTimeout = 20_000
            requestMethod = method
            headers.forEach { (k, v) -> setRequestProperty(k, v) }
            if (body != null) { doOutput = true; setRequestProperty("Content-Type", "application/json") }
        }
        try {
            if (body != null) connection.outputStream.use { it.write(body) }
            val status = connection.responseCode
            require(status == 200) { if (status == 401 || status == 403) "U净登录已失效" else "U净暂时无法连接 ($status)" }
            val bytes = connection.inputStream.use { it.readLimited(1_048_576) }
            val root = JSONObject(bytes.toString(Charsets.UTF_8))
            require(root.optInt("code", -1) == 0) { "U净返回未确认结果" }
            return root
        } finally { connection.disconnect() }
    }

    private fun validateQr(raw: String) {
        val u = URI(raw)
        require(u.scheme == "https" && u.host == "q.ujing.com.cn" && u.port == -1 && u.userInfo == null && u.fragment == null)
        require(u.path == "/ucqrc/index.html")
        val cd = u.rawQuery.orEmpty().split('&').mapNotNull { part ->
            val pair = part.split('=', limit = 2)
            if (pair.firstOrNull() == "cd") pair.getOrNull(1) else null
        }
        require(cd.size == 1 && cd[0].matches(Regex("[0-9]{18}"))) { "二维码不是受支持的 U净机器二维码" }
    }

    private fun jwtClaims(token: String): JSONObject {
        val pieces = token.split('.')
        require(pieces.size == 3)
        val decoded = android.util.Base64.decode(pieces[1], android.util.Base64.URL_SAFE or android.util.Base64.NO_WRAP or android.util.Base64.NO_PADDING)
        require(decoded.size <= 8192)
        return JSONObject(decoded.toString(Charsets.UTF_8))
    }
}

/** Avoid InputStream.readNBytes(), which is unavailable on older Android releases. */
private fun java.io.InputStream.readLimited(limit: Int): ByteArray {
    val out = java.io.ByteArrayOutputStream()
    val buffer = ByteArray(8_192)
    while (true) {
        val count = read(buffer)
        if (count < 0) break
        require(out.size() + count <= limit) { "U净响应过大" }
        out.write(buffer, 0, count)
    }
    return out.toByteArray()
}
