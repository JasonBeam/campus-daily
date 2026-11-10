package com.beamjason.xiaorichang
import com.beamjason.xiaorichang.net.*
import com.beamjason.xiaorichang.data.readAndroidRelease
import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
class ImmediateLaundryTest {
 private val account=UjingAccount("1","1","fixture-token","fixture-client","Test")
 private class Store(var value:CheckoutRecord?):CheckoutStorage {
  var failAttempt=false
  override fun load()=value
  override fun save(record:CheckoutRecord){check(!failAttempt || record.startAttempt!="requested");value=record}
 }
 private class Api: LaundryApi {
  var starts=0;var status="20";var paid="1";var module=7;var fail=false;var wrong=false;var clean=false
  val calls=mutableListOf<String>()
  fun detail()=LaundryOrder("order1",if(wrong)"other" else "device",status,paid,7,"4.00",300,null,"")
  override suspend fun create(account:UjingAccount,snapshot:WasherSnapshot,program:WasherProgram):String=error("unused")
  override suspend fun payment(account:UjingAccount,id:String):JSONObject=error("unused")
  override suspend fun cancel(account:UjingAccount,id:String){error("must not cancel")}
  override suspend fun order(account:UjingAccount,id:String):LaundryOrder{calls+="order";return detail()}
  override suspend fun startDetails(account:UjingAccount,id:String):LaundryStartDetails{calls+="details";return LaundryStartDetails(detail(),module,true,clean)}
  override suspend fun startWasher(account:UjingAccount,id:String){calls+="start";starts++;if(fail)error("timeout");status="40"}
 }
 private fun record(armed:Boolean=true)=CheckoutRecord("1","device",7,"普通洗",400,stage=CheckoutStage.PAYMENT_REQUESTED,orderId="order1",immediateStart=armed)
 @Test fun oneReadBeforeStartAndNoRepeatAfterReload()=runTest {
  val api=Api();val store=Store(record());LaundryCheckout(api,store).refresh(account)
  assertEquals(listOf("details","start","order"),api.calls);LaundryCheckout(api,store).refresh(account)
  assertEquals(1,api.starts);assertEquals("confirmed",store.value?.startAttempt)
 }
 @Test fun uncertainStartOnlyQueriesAfterRestart()=runTest {
  val api=Api().apply{fail=true};val store=Store(record());LaundryCheckout(api,store).refresh(account)
  LaundryCheckout(api,store).refresh(account);assertEquals(1,api.starts);assertEquals("requested",store.value?.startAttempt)
 }
 @Test fun normalUnpaidAndRunningOrdersNeverStart()=runTest {
  for((armed,status,paid) in listOf(Triple(false,"20","1"),Triple(true,"17","0"),Triple(true,"40","1"),Triple(true,"50","1"))){
   val api=Api().apply{this.status=status;this.paid=paid};LaundryCheckout(api,Store(record(armed))).refresh(account);assertEquals(0,api.starts)
  }
 }
 @Test fun storageAndOwnershipMustBeConfirmedBeforeCommand()=runTest {
  val api=Api();val store=Store(record()).apply{failAttempt=true}
  assertTrue(runCatching{LaundryCheckout(api,store).refresh(account)}.isFailure);assertEquals(0,api.starts)
  assertTrue(runCatching{LaundryCheckout(api,Store(record())).refresh(account.copy(id="2"))}.isFailure)
  api.wrong=true;assertTrue(runCatching{LaundryCheckout(api,Store(record())).refresh(account)}.isFailure);assertEquals(0,api.starts)
 }
 @Test fun preparationAndExpiredIntentBlockStart()=runTest {
  for(clean in listOf(true,false)){
   val api=Api().apply{this.clean=clean;module=if(clean)7 else 1};val store=Store(record());LaundryCheckout(api,store).refresh(account)
   assertEquals("blocked",store.value?.startAttempt);assertEquals(0,api.starts)
  }
  val api=Api();val store=Store(record().copy(createdAt=System.currentTimeMillis()-601_000));LaundryCheckout(api,store).refresh(account);assertEquals(0,api.starts)
 }
 @Test fun legacyConsentAndPollingBoundaries() {
  assertFalse(CheckoutRecord.read(record().json().apply{remove("immediateStart")}).immediateStart)
  val r=record();assertEquals(1000L,ImmediatePolling.interval(r,r.createdAt,r.createdAt));assertEquals(3000L,ImmediatePolling.interval(r,r.createdAt,r.createdAt+21_000));assertFalse(ImmediatePolling.needed(r,r.createdAt+601_000))
  assertEquals("/api/v1/app/orders/order1/control/start",immediateOrderPath("order1",true));assertTrue(runCatching{immediateOrderPath("../x",true)}.isFailure)
 }
 @Test fun releaseOriginAndCodeAreValidated() {
  val j=JSONObject("""{"tag_name":"v0.9.0","html_url":"https://github.com/JasonBeam/campus-daily/releases/tag/v0.9.0","assets":[{"name":"CampusDaily-0.3.0-alpha25-code27-debug.apk"}]}""")
  assertEquals(27,readAndroidRelease(j).code)
  assertTrue(runCatching{readAndroidRelease(JSONObject(j.toString()).put("html_url","https://evil.test/"))}.isFailure)
  assertTrue(runCatching{readAndroidRelease(JSONObject(j.toString()).put("prerelease",true))}.isFailure)
 }
}
