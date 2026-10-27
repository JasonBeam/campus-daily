package com.beamjason.xiaorichang.net

import com.beamjason.xiaorichang.data.text
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import org.json.JSONArray
import java.net.URI
import java.net.URLDecoder
import java.math.BigDecimal

fun validOrderId(id:String) = id.matches(Regex("[A-Za-z0-9]{1,80}"))
data class LaundryOrder(val id:String,val deviceId:String,val status:String,val payFlag:String,val programId:Int,
    val priceYuan:String?,val remainSeconds:Int?,val countDown:Int?,val createdAt:String) {
    val terminal get() = status in setOf("50","51","52","53")
    val unpaid get() = status in setOf("10","17") && payFlag=="0"
    val running get() = status in setOf("21","22","24","29","30","35","40")
    val label get() = when(status) { "10" -> "已预约 · 待付款"; "17" -> "待付款"; "20" -> "已付款，等待启动"; "21" -> "正在启动"; "40" -> "洗衣中"; "50" -> "洗衣完成"; "51" -> "付款已超时"; "52" -> "启动失败，请在 U净核对"; "53" -> "订单已取消"; else -> "订单状态待核对" }
    fun json() = JSONObject().put("orderId",id).put("deviceId",deviceId).put("status",status).put("payFlag",payFlag).put("deviceWashModelId",programId)
        .put("payPrice",priceYuan).put("remainTime",remainSeconds).put("countDown",countDown).put("createAt",createdAt)
    companion object {
        fun read(j:JSONObject):LaundryOrder {
            val id=j.text("orderId"); require(validOrderId(id))
            fun seconds(key:String)=j.opt(key)?.takeUnless { it==JSONObject.NULL }?.toString()?.toIntOrNull()?.takeIf { it in 0..604800 }
            val price=j.opt("payPrice")?.takeUnless { it==JSONObject.NULL }?.let(::amount)
            return LaundryOrder(id,j.getString("deviceId"),j.text("status"),j.text("payFlag"),j.optInt("deviceWashModelId",-1),price,seconds("remainTime"),seconds("countDown"),j.text("createAt"))
        }
    }
}

enum class CheckoutStage { CREATING, CREATED, PAYMENT_REQUESTED, CANCELLATION_REQUESTED, COMPLETED }
data class CheckoutRecord(val accountId:String,val deviceId:String,val programId:Int,val programName:String,val priceFen:Int,
    val createdAt:Long = System.currentTimeMillis(),val stage:CheckoutStage = CheckoutStage.CREATING,val orderId:String?=null,
    val order:LaundryOrder?=null,val updatedAt:Long=0) {
    fun json() = JSONObject().put("accountId",accountId).put("deviceId",deviceId).put("programId",programId).put("programName",programName)
        .put("priceFen",priceFen).put("createdAt",createdAt).put("stage",stage.name).put("orderId",orderId).put("order",order?.json()).put("updatedAt",updatedAt)
    companion object { fun read(j:JSONObject) = CheckoutRecord(j.getString("accountId"),j.getString("deviceId"),j.getInt("programId"),j.getString("programName"),j.getInt("priceFen"),j.getLong("createdAt"),
        CheckoutStage.valueOf(j.getString("stage")),j.text("orderId").takeIf(String::isNotBlank),j.optJSONObject("order")?.let(LaundryOrder::read),j.optLong("updatedAt")) }
}

interface LaundryApi {
    suspend fun create(account:UjingAccount,snapshot:WasherSnapshot,program:WasherProgram):String
    suspend fun order(account:UjingAccount,id:String):LaundryOrder
    suspend fun payment(account:UjingAccount,id:String):JSONObject
    suspend fun cancel(account:UjingAccount,id:String)
}
interface CheckoutStorage { fun load():CheckoutRecord?; fun save(record:CheckoutRecord) }

/** Persist before every mutation. Timeouts never cause automatic POST/payment retries. */
class LaundryCheckout(private val api:LaundryApi,private val storage:CheckoutStorage) {
    private val lock=Mutex()
    var record=storage.load(); private set
    var blocked=false; private set
    private fun persist(value:CheckoutRecord) {
        try { storage.save(value); record=value } catch(e:Exception) { blocked=true; throw IllegalStateException("订单无法安全保存，已暂停操作",e) }
    }
    suspend fun create(account:UjingAccount,s:WasherSnapshot,p:WasherProgram) = lock.withLock {
        check(!blocked && (record==null || record?.stage==CheckoutStage.COMPLETED)) { "已有待核对订单，请先查看最近订单" }
        require(s.available && System.currentTimeMillis()-s.fetchedAt in 0..59_999 && s.programs.contains(p) && p.priceFen>=0) { "设备或价格已变化，请刷新后重新确认" }
        var next=CheckoutRecord(account.id,s.id,p.id,p.name,p.priceFen); persist(next)
        val id=api.create(account,s,p); require(validOrderId(id)) { "下单结果不确定，请在 U净核对" }
        next=next.copy(orderId=id); persist(next)
        val detail=api.order(account,id); verify(next,detail)
        persist(next.copy(order=detail,updatedAt=System.currentTimeMillis(),stage=if(detail.terminal) CheckoutStage.COMPLETED else CheckoutStage.CREATED))
    }
    suspend fun refresh(account:UjingAccount) = lock.withLock {
        val old=owned(account); val id=old.orderId ?: error("下单结果未确认，请到官方 U净查看，勿重复预约")
        val detail=api.order(account,id); verify(old,detail)
        persist(old.copy(order=detail,updatedAt=System.currentTimeMillis(),stage=if(detail.terminal) CheckoutStage.COMPLETED else if(old.stage==CheckoutStage.CREATING) CheckoutStage.CREATED else old.stage))
    }
    suspend fun payment(account:UjingAccount):PaymentDestination = lock.withLock {
        var old=owned(account); val id=old.orderId ?: error("订单尚未确认")
        check(old.stage==CheckoutStage.CREATED) { "付款结果待核对，请刷新订单或到支付宝查看" }
        val fresh=api.order(account,id); verify(old,fresh)
        require(fresh.unpaid && fresh.priceYuan!=null && BigDecimal(fresh.priceYuan)>=BigDecimal.ZERO && BigDecimal(fresh.priceYuan)<=BigDecimal(old.priceFen).movePointLeft(2)) { "金额或付款状态已变化，请先刷新订单" }
        old=old.copy(order=fresh,updatedAt=System.currentTimeMillis(),stage=CheckoutStage.PAYMENT_REQUESTED); persist(old)
        PaymentPolicy.destination(api.payment(account,id),BigDecimal(old.priceFen).movePointLeft(2))
    }
    suspend fun cancel(account:UjingAccount) = lock.withLock {
        var old=owned(account); val id=old.orderId ?: error("订单未确认，请到 U净查看")
        check(old.stage in setOf(CheckoutStage.CREATED,CheckoutStage.PAYMENT_REQUESTED)) { "取消结果待核对，请刷新订单" }
        val fresh=api.order(account,id); verify(old,fresh)
        if(fresh.terminal) { persist(old.copy(order=fresh,updatedAt=System.currentTimeMillis(),stage=CheckoutStage.COMPLETED)); return@withLock }
        require(fresh.unpaid) { "订单已付款或已开始，不能取消" }
        old=old.copy(order=fresh,stage=CheckoutStage.CANCELLATION_REQUESTED,updatedAt=System.currentTimeMillis()); persist(old)
        try { api.cancel(account,id) } catch(_:Exception) { /* Only read after an uncertain mutation. */ }
        val final=api.order(account,id); verify(old,final)
        persist(old.copy(order=final,updatedAt=System.currentTimeMillis(),stage=if(final.terminal) CheckoutStage.COMPLETED else CheckoutStage.CANCELLATION_REQUESTED))
        check(final.terminal) { "取消尚未确认，请刷新订单，勿重复操作" }
    }
    private fun owned(a:UjingAccount):CheckoutRecord {
        check(!blocked); val r=record ?: error("还没有洗衣订单"); check(r.accountId==a.id) { "请登录创建此订单的 U净账号" }; return r
    }
    private fun verify(r:CheckoutRecord,o:LaundryOrder) {
        require(o.id==r.orderId && o.deviceId==r.deviceId && o.programId==r.programId) { "订单与本次预约不匹配，请在官方 U净核对" }
    }
}

sealed class PaymentDestination { data object Query:PaymentDestination(); data class Checkout(val url:String):PaymentDestination(); data class Signed(val value:String):PaymentDestination() }
object PaymentPolicy {
    private fun query(uri:URI):Map<String,String> {
        val pairs=uri.rawQuery.orEmpty().split('&').filter(String::isNotEmpty).map { val p=it.split('=',limit=2); URLDecoder.decode(p[0],"UTF-8") to URLDecoder.decode(p.getOrElse(1){""},"UTF-8") }
        require(pairs.map { it.first }.distinct().size==pairs.size); return pairs.toMap()
    }
    fun allowedCheckout(value:String):Boolean = runCatching {
        require(value.length<=16384); val u=URI(value)
        require(u.userInfo==null && u.port==-1 && u.fragment==null)
        if(u.scheme=="https" && u.host=="qr.alipay.com" && !u.path.isNullOrBlank()) return@runCatching true
        require(u.scheme=="alipays" && u.host=="platformapi" && u.path=="/startApp")
        val q=query(u); require(q["appId"]=="20000042" && q["actionType"]=="WebView" && q["followType"]=="PUBLIC")
        val auth=URI(q["url"] ?: error("missing auth")); require(auth.scheme=="https" && auth.host=="openauth.alipay.com" && auth.path=="/oauth2/publicAppAuthorize.htm" && auth.userInfo==null && auth.port==-1 && auth.fragment==null)
        val target=URI(query(auth)["redirect_uri"] ?: error("missing redirect"))
        target.scheme=="https" && target.host=="wx.zhinengxiyifang.cn" && target.path=="/static/commonWasher/index.html" && target.userInfo==null && target.port==-1 && target.fragment==null
    }.getOrDefault(false)
    fun validSigned(value:String,maximum:BigDecimal):Boolean = runCatching {
        require(value.length<=65536); val q=query(URI("https://localhost/?$value"))
        require(q["method"]=="alipay.trade.app.pay" && !q["sign"].isNullOrBlank())
        val raw=JSONObject(q["biz_content"] ?: error("missing amount")).getString("total_amount")
        require(raw.matches(Regex("[0-9]+(\\.[0-9]{1,2})?")))
        val amount=BigDecimal(raw); amount>BigDecimal.ZERO && amount<=maximum
    }.getOrDefault(false)
    fun destination(j:JSONObject,maximum:BigDecimal):PaymentDestination {
        fun flag(key:String)=j.opt(key)?.toString() in setOf("true","1")
        if(flag("skipPay") || flag("jumpToQuery")) return PaymentDestination.Query
        fun checkout(value:Any?,depth:Int=0):String? {
            if(depth>8) return null
            return when(value) {
                is String -> value.takeIf(::allowedCheckout)
                is JSONObject -> value.keys().asSequence().mapNotNull { checkout(value.opt(it),depth+1) }.firstOrNull()
                is JSONArray -> (0 until value.length()).asSequence().mapNotNull { checkout(value.opt(it),depth+1) }.firstOrNull()
                else -> null
            }
        }
        checkout(j)?.let { return PaymentDestination.Checkout(it) }
        val signed=j.optJSONObject("payInfo")?.text("orderInfo")?.takeIf(String::isNotBlank) ?: j.text("orderInfo")
        if(validSigned(signed,maximum)) return PaymentDestination.Signed(signed)
        error("该订单未返回可用付款入口，请到官方 U净核对")
    }
}
