package com.beamjason.xiaorichang

import com.beamjason.xiaorichang.net.*
import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.math.BigDecimal
import java.net.URLEncoder

class LaundrySafetyTest {
    private val account=UjingAccount("1","1","not-a-real-token","demo-client","CampusDailyTest")
    private val program=WasherProgram(7,"标准洗",40,400)
    private fun snapshot()=WasherSnapshot("device1","demo","测试机器","测试位置",0,true,listOf(program),"store",1)
    private fun order(price:String="4.00",status:String="10",paid:String="0",device:String="device1")=LaundryOrder("order1",device,status,paid,7,price,null,600,"")
    private class MemoryStore:CheckoutStorage {
        var value:CheckoutRecord?=null
        var fail=false
        override fun load()=value
        override fun save(record:CheckoutRecord) {check(!fail){"disk full"};value=record}
    }
    private class Api: LaundryApi {
        var creates=0;var pays=0;var cancels=0;var reads=0
        var createFails=false;var payFails=false;var cancelFails=false
        var detail=LaundryOrder("order1","device1","10","0",7,"4.00",null,600,"")
        var beforeCreate:()->Unit={};var beforeRead:()->Unit={}
        override suspend fun create(account:UjingAccount,snapshot:WasherSnapshot,program:WasherProgram):String {creates++;beforeCreate();if(createFails)error("timeout");return "order1"}
        override suspend fun order(account:UjingAccount,id:String):LaundryOrder {reads++;beforeRead();return detail}
        override suspend fun payment(account:UjingAccount,id:String):JSONObject {pays++;if(payFails)error("timeout");return JSONObject().put("skipPay",true)}
        override suspend fun cancel(account:UjingAccount,id:String) {cancels++;detail=detail.copy(status="53");if(cancelFails)error("timeout")}
    }
    @Test fun durableMarkerPrecedesCreateAndIdPrecedesDetail()=runTest {
        val store=MemoryStore();val api=Api();val c=LaundryCheckout(api,store)
        api.beforeCreate={assertEquals(CheckoutStage.CREATING,store.value?.stage)}
        api.beforeRead={assertEquals("order1",store.value?.orderId)}
        c.create(account,snapshot(),program);assertEquals(CheckoutStage.CREATED,c.record?.stage)
    }
    @Test fun uncertainCreateCannotBeRepeatedAfterReload()=runTest {
        val store=MemoryStore();val api=Api().apply{createFails=true};val c=LaundryCheckout(api,store)
        assertTrue(runCatching {c.create(account,snapshot(),program)}.isFailure)
        val reloaded=LaundryCheckout(api,store)
        assertTrue(runCatching {reloaded.create(account,snapshot(),program)}.isFailure);assertEquals(1,api.creates)
    }
    @Test fun persistenceFailurePreventsRemoteMutation()=runTest {
        val store=MemoryStore().apply{fail=true};val api=Api();val c=LaundryCheckout(api,store)
        assertTrue(runCatching {c.create(account,snapshot(),program)}.isFailure);assertTrue(c.blocked);assertEquals(0,api.creates)
    }
    @Test fun staleOrBusyDeviceCannotCreate()=runTest {
        val api=Api();val c=LaundryCheckout(api,MemoryStore())
        assertTrue(runCatching {c.create(account,snapshot().copy(fetchedAt=0),program)}.isFailure)
        assertTrue(runCatching {c.create(account,snapshot().copy(activeOrderId="someoneElse"),program)}.isFailure);assertEquals(0,api.creates)
    }
    @Test fun wrongDetailKeepsDurableOrderIdWithoutEnablingPayment()=runTest {
        val api=Api().apply{detail=order(device="wrong")};val store=MemoryStore();val c=LaundryCheckout(api,store)
        assertTrue(runCatching {c.create(account,snapshot(),program)}.isFailure);assertEquals("order1",store.value?.orderId);assertEquals(CheckoutStage.CREATING,store.value?.stage)
    }
    @Test fun increasedPriceBlocksPaymentArguments()=runTest {
        val api=Api();val c=LaundryCheckout(api,MemoryStore());c.create(account,snapshot(),program);api.detail=order("4.01")
        assertTrue(runCatching {c.payment(account)}.isFailure);assertEquals(0,api.pays)
    }
    @Test fun paymentTimeoutIsNotResetByRefreshOrRestart()=runTest {
        val api=Api();val store=MemoryStore();val c=LaundryCheckout(api,store);c.create(account,snapshot(),program);api.payFails=true
        assertTrue(runCatching {c.payment(account)}.isFailure);c.refresh(account)
        val next=LaundryCheckout(api,store);assertTrue(runCatching {next.payment(account)}.isFailure);assertEquals(1,api.pays)
    }
    @Test fun paidOrderCannotBeCancelled()=runTest {
        val api=Api();val c=LaundryCheckout(api,MemoryStore());c.create(account,snapshot(),program);api.detail=order(status="20",paid="1")
        assertTrue(runCatching {c.cancel(account)}.isFailure);assertEquals(0,api.cancels)
    }
    @Test fun cancellationTimeoutIsVerifiedWithReadOnlyQuery()=runTest {
        val api=Api();val c=LaundryCheckout(api,MemoryStore());c.create(account,snapshot(),program);api.cancelFails=true
        c.cancel(account);assertEquals(1,api.cancels);assertEquals(CheckoutStage.COMPLETED,c.record?.stage)
    }
    @Test fun wrongAccountCannotInspectOrMutateOrder()=runTest {
        val api=Api();val c=LaundryCheckout(api,MemoryStore());c.create(account,snapshot(),program);val reads=api.reads
        assertTrue(runCatching {c.refresh(account.copy(id="2"))}.isFailure);assertEquals(reads,api.reads)
    }
    @Test fun corruptOrderStoreFailsClosed() {
        val broken=object:CheckoutStorage{override fun load():CheckoutRecord?=error("corrupt");override fun save(record:CheckoutRecord){}}
        assertTrue(runCatching {LaundryCheckout(Api(),broken)}.isFailure)
    }
    @Test fun onlyObservedCheckoutOriginsAreAccepted() {
        assertTrue(PaymentPolicy.allowedCheckout("https://qr.alipay.com/demo"))
        listOf("http://qr.alipay.com/demo","https://qr.alipay.com.evil.test/demo","https://attacker@qr.alipay.com/demo","https://qr.alipay.com:8443/demo","javascript:alert(1)","alipays://platformapi/startApp?appId=wrong").forEach{assertFalse(it,PaymentPolicy.allowedCheckout(it))}
    }
    @Test fun f2fRedirectIsValidatedThroughBothNestedOrigins() {
        fun enc(v:String)=URLEncoder.encode(v,"UTF-8")
        val target="https://wx.zhinengxiyifang.cn/static/commonWasher/index.html"
        val auth="https://openauth.alipay.com/oauth2/publicAppAuthorize.htm?redirect_uri=${enc(target)}"
        val value="alipays://platformapi/startApp?appId=20000042&actionType=WebView&followType=PUBLIC&url=${enc(auth)}"
        assertTrue(PaymentPolicy.allowedCheckout(value));assertFalse(PaymentPolicy.allowedCheckout(value+"&appId=evil"))
        assertFalse(PaymentPolicy.allowedCheckout(value.replace("wx.zhinengxiyifang.cn","evil.test")))
    }
    @Test fun signedAmountAndDuplicateKeysAreRejected() {
        fun value(price:String)="method=alipay.trade.app.pay&sign=test&biz_content="+URLEncoder.encode("""{"total_amount":"$price"}""","UTF-8")
        assertTrue(PaymentPolicy.validSigned(value("4.00"),BigDecimal("4.00")))
        listOf(value("4.01"),value("-1"),value("1e3"),value("0"),value("4.00")+"&method=alipay.trade.app.pay").forEach{assertFalse(PaymentPolicy.validSigned(it,BigDecimal("4.00")))}
    }
    @Test fun schoolSessionRequiresIdentityAndRejectsControlCharacters() {
        assertTrue(runCatching{parseOfficialSession(JSONObject())}.isFailure)
        val root=JSONObject().put("loginInfo",JSONObject().put("syscustid","demo").put("custid","card")).put("logintoken","demo\nsecret").put("schoolid","school")
        assertTrue(runCatching{parseOfficialSession(root)}.isFailure)
    }
}
