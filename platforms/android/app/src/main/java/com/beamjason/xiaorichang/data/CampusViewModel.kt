package com.beamjason.xiaorichang.data

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.beamjason.xiaorichang.ble.*
import com.beamjason.xiaorichang.net.*
import com.beamjason.xiaorichang.security.SecureStore
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import org.json.JSONArray
import org.json.JSONObject

data class DormSetup(val identity:DormIdentity?=null,val levels:List<List<Option>> = emptyList(),val path:List<Option> = emptyList(),
    val machines:List<DormWater> = emptyList(),val selected:DormWater?=null,val candidates:List<BleCandidate> = emptyList(),val verifiedAddress:String?=null,
    val readIdentities:Map<String,String> = emptyMap(),val checkingAddress:String?=null,val suggestedPower:CampusPowerSuggestion?=null,val autoMatched:Boolean=false)
data class PowerSetup(val options:List<Option> = emptyList(),val path:List<Option> = emptyList(),val meters:List<PowerMeter> = emptyList())
data class CampusUiState(val campus:CampusConfig=CampusConfig(),val water:WaterSettings=WaterSettings(),val account:UjingAccount?=null,
    val washers:List<SavedWasher> = emptyList(),val selectedWasher:String?=null,val washer:WasherSnapshot?=null,val cache:BalanceCache=BalanceCache(),
    val cardError:String?=null,val powerError:String?=null,val washerError:String?=null,val waterSession:ShowerSession?=null,
    val checkout:CheckoutRecord?=null,val busy:Set<String> = emptySet(),val message:String?=null,val storageIssue:Boolean=false,
    val dormSetup:DormSetup=DormSetup(),val powerSetup:PowerSetup=PowerSetup(),val webSession:CampusWebSession?=null) {
    val setupCount get() = (if(campus.configured) 1 else 0)+(if(water.configured) 1 else 0)+(if(account!=null && washers.isNotEmpty()) 1 else 0)
    val unresolvedWater get() = waterSession!=null && waterSession.stage!=ShowerStage.SETTLED
    val unresolvedLaundry get() = checkout!=null && checkout.stage!=CheckoutStage.COMPLETED
    val transactionBusy get() = busy.any { it in setOf("water","verify","order","payment","cancel","orderRefresh") }
}

/** State is retained across Activity recreation; credentials and transaction markers
 * are encrypted before writes. UI never owns network calls or transaction state. */
class CampusViewModel(application:Application):AndroidViewModel(application) {
    private val secure=SecureStore(application)
    private val campusApi=CampusClient()
    private val laundryApi=UjingClient()
    private val transport=BleWaterTransport(application)
    private val waterController=WaterController(application,transport)
    private var startupError=false
    private fun read(key:String):JSONObject? = try { secure.get(key)?.let { JSONObject(it.toString(Charsets.UTF_8)) } }
        catch(_:Exception) { startupError=true; null }
    private fun write(key:String,value:JSONObject) { secure.put(key,value.toString().toByteArray()) }
    private fun saveSettings(campus:CampusConfig,water:WaterSettings) {
        // One authenticated ciphertext + one committed preference update: dorm,
        // account and selected controller cannot be half-written independently.
        write("app.settings.v2",JSONObject().put("campus",campus.json()).put("water",water.json()))
    }
    private val checkoutController: LaundryCheckout? = try {
        LaundryCheckout(laundryApi,object:CheckoutStorage {
            override fun load()=secure.get("laundry.checkout")?.let { CheckoutRecord.read(JSONObject(it.toString(Charsets.UTF_8))) }
            override fun save(record:CheckoutRecord) { write("laundry.checkout",record.json()) }
        })
    } catch(_:Exception) { startupError=true; null }
    private val _state=MutableStateFlow(load())
    val state=_state.asStateFlow()
    private val attempts=mutableMapOf<String,Long>()
    init { provisionDevelopmentPlatform() }

    // Developer-controlled test devices can be prepared over their authorized
    // USB connection. No platform key is compiled into the public APK.
    private fun provisionDevelopmentPlatform() {
        if(!com.beamjason.xiaorichang.BuildConfig.DEBUG)return
        val file=java.io.File(getApplication<Application>().noBackupFilesDir,"development-water-platform.json")
        if(!file.isFile)return
        val current=_state.value
        if(current.unresolvedWater || current.transactionBusy || current.storageIssue)return
        try {
            if(!current.water.hasPlatform) {
                require(file.length()<=8192)
                val seed=parseDevelopmentPlatform(file.readText())
                saveSettings(current.campus,seed)
                _state.update{it.copy(water=seed,dormSetup=DormSetup(),message="热水接入已准备，可选择自己的宿舍")}
            }
            check(file.delete())
        } catch(_:Exception) {notice("热水接入准备未完成，请联系内测提供者核对")}
    }

    private fun load():CampusUiState {
        fun <T> parse(key:String,block:(JSONObject)->T):T? = read(key)?.let { try { block(it) } catch(_:Exception) { startupError=true; null } }
        val settings=read("app.settings.v2")
        val campus=if(settings!=null) try {readCampus(settings.getJSONObject("campus"))} catch(_:Exception){startupError=true;CampusConfig()}
            else parse("campus.config",::readCampus) ?: CampusConfig()
        val water=if(settings!=null) try {WaterSettings.read(settings.getJSONObject("water"))} catch(_:Exception){startupError=true;WaterSettings()}
            else parse("water.profile",WaterSettings::read) ?: WaterSettings()
        val account=parse("ujing.account",::readAccount)
        val washers=parse("ujing.washers") { j -> val rows=j.getJSONArray("items"); require(rows.length()<=100); (0 until rows.length()).map { SavedWasher.read(rows.getJSONObject(it)) } } ?: emptyList()
        val cache=parse("campus.balance-cache",BalanceCache::read)?.takeIf { it.owner==campus.owner } ?: BalanceCache(owner=campus.owner)
        return CampusUiState(campus,water,account,washers,read("ujing.selection")?.text("id") ?: washers.firstOrNull()?.id,
            cache=cache,waterSession=waterController.session,checkout=checkoutController?.record,
            storageIssue=startupError || waterController.blocked,
            message=if(startupError || waterController.blocked) "本机加密记录读取失败，请保留 App 数据并联系开发者核对，暂不可进行交易" else null)
    }
    private fun transactionAllowed() { check(!_state.value.storageIssue) { "加密记录尚未核对，已暂停交易" } }
    private fun action(key:String,block:suspend ()->Unit) {
        if(key in _state.value.busy) return
        _state.update { it.copy(busy=it.busy+key,message=null) }
        viewModelScope.launch {
            try { block() }
            catch(e:CancellationException) { throw e }
            catch(e:Exception) { _state.update { it.copy(message=message(e)) } }
            finally { _state.update { it.copy(busy=it.busy-key,waterSession=waterController.session,checkout=checkoutController?.record,
                storageIssue=it.storageIssue || waterController.blocked || checkoutController?.blocked==true) } }
        }
    }
    fun notice(value:String?) { _state.update { it.copy(message=value) } }
    fun resume() { provisionDevelopmentPlatform(); refresh(); if(_state.value.checkout?.orderId!=null) refreshOrder(false); selectedWasher()?.let { refreshWasher(it,false) } }
    fun refresh(force:Boolean=false) {
        val c=_state.value.campus; if(!c.configured) return
        fun due(key:String):Boolean {
            val now=System.currentTimeMillis(); if(now-(attempts[key] ?: 0)<if(force) 5_000 else 300_000) return false
            attempts[key]=now; return true
        }
        if(due("card")) action("card") {
            try {
                val value=campusApi.balance(c); if(_state.value.campus!=c) return@action
                val next=_state.value.cache.copy(card=value,cardAt=System.currentTimeMillis()); write("campus.balance-cache",next.json())
                _state.update { it.copy(cache=next,cardError=null) }
            } catch(e:Exception) { if(e is CancellationException) throw e; if(_state.value.campus==c) _state.update { it.copy(cardError=message(e)) } }
        }
        if(c.buildingId.isNotBlank() && due("power")) action("power") {
            try {
                val value=campusApi.electricity(c); if(_state.value.campus!=c) return@action
                val next=_state.value.cache.copy(power=value,powerAt=System.currentTimeMillis()); write("campus.balance-cache",next.json())
                _state.update { it.copy(cache=next,powerError=null) }
            } catch(e:Exception) { if(e is CancellationException) throw e; if(_state.value.campus==c) _state.update { it.copy(powerError=message(e)) } }
        }
    }
    fun acceptLogin(c:CampusConfig,onSaved:()->Unit={}) = action("login") {
        transactionAllowed(); check(!_state.value.transactionBusy && !_state.value.unresolvedWater && !_state.value.unresolvedLaundry) { "请先完成或核对当前订单，再更换学校账号" }
        val old=_state.value.campus
        val own=c.copy(dorm=PortalDormAddress.parse(c.portalDormAddress)?.shortRoom.orEmpty())
        val next=if(old.syscustid==c.syscustid && old.areaCode==c.areaCode) own.copy(dorm=old.dorm.ifBlank{own.dorm},buildingId=old.buildingId,meterId=old.meterId,portalDormAddress=c.portalDormAddress.ifBlank{old.portalDormAddress}) else own
        val changed=old.syscustid!=c.syscustid || old.areaCode!=c.areaCode
        val water=if(changed) _state.value.water.copy(studentId="",schoolId="",machineId="",address=null,room="") else _state.value.water
        saveSettings(next,water)
        _state.update { it.copy(campus=next,water=if(changed) it.water.copy(studentId="",schoolId="",machineId="",address=null,room="") else it.water,
            cache=if(changed) BalanceCache(owner=next.owner) else it.cache,cardError=null,powerError=null,webSession=null,dormSetup=DormSetup(),message="学校账号已保存") }
        attempts.clear(); onSaved(); refresh(true)
    }
    fun importConfig(text:String) = action("import") {
        transactionAllowed(); require(text.toByteArray().size<=65536); check(!_state.value.unresolvedWater && !_state.value.transactionBusy) { "请先核对当前热水会话" }
        val root=JSONObject(text); val raw=root.optJSONObject("water") ?: root.optJSONObject("platform") ?: root
        val w=WaterSettings.read(raw); require(w.hasPlatform) { "请选择热水平台配置或本人 waterconfig 文件" }
        require(w.secret.length<=256 && w.sid.length<=128 && w.bleName.length<=64)
        // Imported MAC/address is never treated as physically verified.
        val safe=w.copy(address=null)
        if(safe.machineId.isNotBlank()) safe.profile().validate()
        saveSettings(_state.value.campus,safe); _state.update { it.copy(water=safe,dormSetup=DormSetup(),message="热水配置已导入，可继续选择自己的宿舍") }
    }
    fun loadDorm() = action("dorm") {
        val s=_state.value; require(s.campus.configured) { "请先登录学校账号" }; require(s.water.hasPlatform) { "热水接入尚未准备，请先完成内测初始化" }
        check(!s.unresolvedWater) { "当前有未完成热水会话，暂不能更换设备" }
        val identity=campusApi.readDormIdentity(s.campus,s.water.platform())
        val root=campusApi.dormOptions(identity.schoolId,false,s.water.platform())
        var draft=autoSingleDorm(s,DormSetup(identity=identity,levels=listOf(root)))
        val address=PortalDormAddress.parse(s.campus.portalDormAddress)
        if(address!=null) {
            while(draft.path.size<4) {
                val level=draft.path.size
                val option=draft.levels.getOrNull(level)?.filter{address.matches(it.name,level)}?.singleOrNull() ?: break
                val path=draft.path+option
                draft=if(level==3)draft.copy(path=path,machines=campusApi.waterMachines(option.id,identity.schoolId,s.water.platform()))
                    else draft.copy(path=path,levels=draft.levels+listOf(campusApi.dormOptions(option.id,level==2,s.water.platform())))
            }
            if(draft.path.size==4 && draft.path.withIndex().all{(level,option)->address.matches(option.name,level)}) {
                val power=try {withTimeoutOrNull(15_000){campusApi.suggestPower(s.campus,address)}} catch(e:CancellationException){throw e}catch(_:Exception){null}
                draft=draft.copy(autoMatched=true,selected=draft.machines.singleOrNull(),suggestedPower=power)
            }
        }
        check(_state.value.campus==s.campus && _state.value.water==s.water) { "学校账号或宿舍已变化，请重新读取" }
        _state.update { it.copy(dormSetup=draft) }
        require(root.isNotEmpty()) { "学校未返回宿舍列表，请稍后重试" }
    }
    fun chooseDorm(option:Option,level:Int) = action("dorm") {
        val s=_state.value; check(!s.unresolvedWater); val d=s.dormSetup; val who=d.identity ?: error("请先读取本人宿舍信息")
        require(level in 0..3 && d.levels.getOrNull(level)?.contains(option)==true)
        val path=d.path.take(level)+option
        if(level==3) {
            val machines=campusApi.waterMachines(option.id,who.schoolId,s.water.platform())
            check(_state.value.campus==s.campus && _state.value.water==s.water)
            _state.update { it.copy(dormSetup=d.copy(path=path,levels=d.levels.take(4),machines=machines,selected=null,candidates=emptyList(),verifiedAddress=null,readIdentities=emptyMap(),checkingAddress=null,suggestedPower=null,autoMatched=false)) }
            require(machines.isNotEmpty()) { "该寝室未返回水控，请重新核对房间" }
        } else {
            val next=campusApi.dormOptions(option.id,level==2,s.water.platform())
            val draft=autoSingleDorm(s,d.copy(path=path,levels=d.levels.take(level+1)+listOf(next),machines=emptyList(),selected=null,candidates=emptyList(),verifiedAddress=null,readIdentities=emptyMap(),checkingAddress=null,suggestedPower=null,autoMatched=false))
            check(_state.value.campus==s.campus && _state.value.water==s.water)
            _state.update { it.copy(dormSetup=draft) }
        }
    }
    private suspend fun autoSingleDorm(s:CampusUiState,initial:DormSetup):DormSetup {
        var d=initial
        while(d.path.size<4) {
            val level=d.path.size;val only=d.levels.getOrNull(level)?.singleOrNull() ?: break
            val path=d.path+only
            d=if(level==3) d.copy(path=path,machines=campusApi.waterMachines(only.id,d.identity!!.schoolId,s.water.platform()))
                else d.copy(path=path,levels=d.levels+listOf(campusApi.dormOptions(only.id,level==2,s.water.platform())))
        }
        // Never automatically select a water controller, even when the server lists only one.
        return d
    }
    fun selectMachine(m:DormWater) {
        val d=_state.value.dormSetup; if(m !in d.machines) return
        _state.update { it.copy(dormSetup=d.copy(selected=m,candidates=emptyList(),verifiedAddress=null,readIdentities=emptyMap(),checkingAddress=null)) }
    }
    fun scanWater() = action("verify") {
        val s=_state.value
        check(s.busy.none { it in setOf("water","order","payment","cancel") } && !s.unresolvedWater)
        val machine=s.dormSetup.selected ?: error("请先选择学校返回的水控")
        val found=transport.scanCandidates(s.water.bleName)
        fun stillCurrent() = _state.value.campus==s.campus && _state.value.water==s.water && _state.value.dormSetup.selected==machine
        check(stillCurrent()){ "宿舍已变化，请重新扫描" }
        _state.update { it.copy(dormSetup=it.dormSetup.copy(candidates=found,verifiedAddress=null,readIdentities=emptyMap(),checkingAddress=null)) }
        require(found.isNotEmpty()) { "未发现水控，请靠近设备、打开蓝牙后重试" }
        try {
            for(candidate in found.take(8)) {
                check(stillCurrent()){ "宿舍已变化，请重新扫描" }
                _state.update{it.copy(dormSetup=it.dormSetup.copy(checkingAddress=candidate.address))}
                val actual=try {
                    withTimeoutOrNull(9_000) {
                        transport.connect(s.water.bleName,candidate.address)
                        com.beamjason.xiaorichang.core.WaterProtocol.identity(transport.exchange(byteArrayOf(0xAA.toByte())))
                    }
                } catch(e:CancellationException){throw e}
                  catch(_:Exception){null}
                finally {transport.disconnect()}
                check(stillCurrent()){ "宿舍已变化，请重新扫描" }
                if(actual!=null) {
                    val matches=actual.equals(machine.machineId,true)
                    _state.update {it.copy(dormSetup=it.dormSetup.copy(readIdentities=it.dormSetup.readIdentities+(candidate.address to actual),verifiedAddress=if(matches)candidate.address else null))}
                    if(matches){notice("已找到本宿舍水控并核对编号");return@action}
                }
            }
            notice("未找到匹配的宿舍水控，请靠近设备后重试")
        } finally {_state.update{it.copy(dormSetup=it.dormSetup.copy(checkingAddress=null))}}
    }
    fun verifyWater(candidate:BleCandidate) = action("verify") {
        val s=_state.value; check(!s.unresolvedWater); val m=s.dormSetup.selected ?: error("请先选择学校返回的水控")
        require(candidate in s.dormSetup.candidates)
        try {
            transport.connect(s.water.bleName,candidate.address)
            val actual=com.beamjason.xiaorichang.core.WaterProtocol.identity(transport.exchange(byteArrayOf(0xAA.toByte())))
            require(actual.equals(m.machineId,true)) { "这台蓝牙水控与所选编号不一致，请选择另一台" }
            _state.update { it.copy(dormSetup=it.dormSetup.copy(verifiedAddress=candidate.address,readIdentities=it.dormSetup.readIdentities+(candidate.address to actual)),message="已通过蓝牙读取并核对水控编号") }
        } finally { transport.disconnect() }
    }
    fun saveDorm() = action("saveDorm") {
        transactionAllowed(); val s=_state.value; check(!s.unresolvedWater && !s.transactionBusy)
        val d=s.dormSetup; val m=d.selected ?: error("请选择自己的水控"); val who=d.identity ?: error("本人身份尚未读取")
        require(d.path.size==4); val room=d.path[1].name+d.path[3].name
        val water=s.water.copy(studentId=who.studentId,schoolId=who.schoolId,machineId=m.machineId,address=d.verifiedAddress,room=room)
        water.profile().validate()
        val power=d.suggestedPower
        val address=PortalDormAddress.parse(s.campus.portalDormAddress)
        val portalMatches=address!=null && d.path.withIndex().all{(level,option)->address.matches(option.name,level)}
        val keepPower=portalMatches && s.cache.power?.let{address!!.matchesMeterRoom(it.room)}==true
        val c=s.campus.copy(dorm=room,buildingId=power?.building ?: if(keepPower)s.campus.buildingId else "",meterId=power?.meter?.id ?: if(keepPower)s.campus.meterId else "")
        val cache=if(power!=null)s.cache.copy(power=power.meter,powerAt=System.currentTimeMillis()) else if(keepPower)s.cache else s.cache.copy(power=null,powerAt=0)
        saveSettings(c,water);write("campus.balance-cache",cache.json())
        _state.update { it.copy(water=water,campus=c,cache=cache,message=if(power!=null)"宿舍、热水和电表已同步保存" else if(water.address!=null) "宿舍和已核对水控已保存" else "宿舍已保存，首次开始时会读取并核对水控编号") }
    }
    fun loadPower() = action("powerSetup") {
        val c=_state.value.campus; require(c.configured) { "请先登录学校账号" }
        val values=campusApi.powerBuildings(c)
        check(_state.value.campus==c) { "账号已变化，请重新读取" }
        _state.update { it.copy(powerSetup=PowerSetup(options=values)) }
    }
    fun choosePower(option:Option) = action("powerSetup") {
        val s=_state.value; require(option in s.powerSetup.options)
        val children=campusApi.powerBuildings(s.campus,option.id)
        val meters=if(children.isEmpty()) campusApi.powerMeters(s.campus,option.id) else emptyList()
        check(_state.value.campus==s.campus) { "账号已变化，请重新读取" }
        _state.update { it.copy(powerSetup=PowerSetup(children,s.powerSetup.path+option,meters)) }
        require(children.isNotEmpty() || meters.isNotEmpty()) { "此位置未返回电表，请重新选择" }
    }
    fun saveMeter(m:PowerMeter) = action("saveMeter") {
        val s=_state.value; require(m in s.powerSetup.meters); val building=s.powerSetup.path.lastOrNull()?.id ?: error("位置未确认")
        val c=s.campus.copy(buildingId=building,meterId=m.id); saveSettings(c,s.water)
        _state.update {it.copy(campus=c)}
        val cache=s.cache.copy(power=m,powerAt=System.currentTimeMillis()); write("campus.balance-cache",cache.json())
        _state.update { it.copy(campus=c,cache=cache,powerError=null,message="宿舍电表已绑定") }
    }
    fun prepareRecharge() = action("recharge") {
        _state.update { it.copy(webSession=null) }; val c=_state.value.campus
        val result=campusApi.webSession(c); check(_state.value.campus==c) { "账号已变化，请重试" }
        _state.update { it.copy(webSession=result) }
    }
    fun operateWater(finish:Boolean) = action("water") {
        transactionAllowed(); check(!_state.value.busy.contains("verify"))
        val w=_state.value.water; require(w.configured) { "请先选择宿舍和水控" }
        try {
            if(finish) waterController.finish(w.profile()) else waterController.start(w.profile(),w.address)
            notice(if(finish) "服务器已确认结算，请同时确认现场已停水" else "水控已确认授权，请按水控上的出水键")
        } finally { _state.update { it.copy(waterSession=waterController.session) } }
    }
    fun sendCode(phone:String) = action("sms") { laundryApi.sendCode(phone); notice("验证码已发送，请查看本人短信") }
    fun loginLaundry(phone:String,code:String) = action("laundryLogin") {
        transactionAllowed(); val s=_state.value; check(!s.transactionBusy && !s.unresolvedLaundry) { "请先完成或核对当前洗衣订单" }
        val a=laundryApi.login(phone,code); write("ujing.account",a.json())
        _state.update { it.copy(account=a,washer=null,washerError=null,message="U净登录成功，可扫描洗衣机") }
    }
    fun selectedWasher()=_state.value.washers.firstOrNull { it.id==_state.value.selectedWasher }
    fun selectWasher(w:SavedWasher) = action("selectWasher") {
        if(w !in _state.value.washers || _state.value.transactionBusy) return@action
        write("ujing.selection",JSONObject().put("id",w.id)); _state.update { it.copy(selectedWasher=w.id,washer=null,washerError=null) }; refreshWasher(w,true)
    }
    fun scanWasher(qr:String) = action("washer") {
        val s=_state.value; val a=s.account ?: error("请先登录 U净")
        val snap=laundryApi.discoverAndRead(a,qr); check(_state.value.account==a)
        val saved=SavedWasher(snap.id,qr,snap.title,snap.number)
        val items=s.washers.filter { it.id!=saved.id }+saved; require(items.size<=100)
        write("ujing.washers",JSONObject().put("items",JSONArray(items.map { it.json() }))); write("ujing.selection",JSONObject().put("id",saved.id))
        _state.update { it.copy(washers=items,selectedWasher=saved.id,washer=snap,washerError=null,message="洗衣机已保存，下次直接打开") }
    }
    fun refreshWasher(w:SavedWasher?=selectedWasher(),force:Boolean=true) {
        w ?: return; val a=_state.value.account ?: return; val key="washer:${w.id}"; val now=System.currentTimeMillis()
        if(now-(attempts[key] ?: 0)<if(force) 3_000 else 30_000) return; attempts[key]=now
        action("washer") {
            try {
                val snap=laundryApi.discoverAndRead(a,w.qr); require(snap.id==w.id) { "二维码对应的设备已变化，请重新扫码" }
                if(_state.value.account==a && _state.value.selectedWasher==w.id) _state.update { it.copy(washer=snap,washerError=null) }
            } catch(e:Exception) { if(e is CancellationException) throw e; _state.update { it.copy(washerError=message(e)) } }
        }
    }
    fun createOrder(program:WasherProgram) = action("order") {
        transactionAllowed(); val s=_state.value; val a=s.account ?: error("请先登录 U净"); val previous=s.washer ?: error("请先刷新洗衣机")
        val w=selectedWasher() ?: error("请选择洗衣机")
        val fresh=laundryApi.discoverAndRead(a,w.qr); require(fresh.id==previous.id && fresh.programs.contains(program)) { "设备或价格已变化，请重新确认" }
        _state.update { it.copy(washer=fresh) }; val controller=checkoutController ?: error("订单存储不可用")
        controller.create(a,fresh,program); notice("预约已确认，请查看订单后前往支付宝付款")
    }
    fun refreshOrder(force:Boolean=true) {
        val a=_state.value.account ?: return; val r=_state.value.checkout ?: return
        if(r.accountId!=a.id || r.orderId==null || (!force && r.stage==CheckoutStage.COMPLETED)) return
        val now=System.currentTimeMillis(); if(now-(attempts["order"] ?: 0)<3_000) return; attempts["order"]=now
        action("orderRefresh") { checkoutController?.refresh(a) }
    }
    fun payOrder(open:(PaymentDestination)->Unit) = action("payment") {
        transactionAllowed(); val a=_state.value.account ?: error("请登录创建订单的 U净账号")
        val dest=checkoutController?.payment(a) ?: error("订单记录不可用")
        open(dest)
    }
    fun cancelOrder() = action("cancel") {
        transactionAllowed(); val a=_state.value.account ?: error("请先登录 U净")
        checkoutController?.cancel(a); notice("已核对服务器返回的订单状态")
    }
    override fun onCleared() { transport.disconnect(); super.onCleared() }
}

fun message(e:Throwable):String = when(e) {
    is java.net.UnknownHostException -> "网络暂时不可用，已保留上次数据"
    is java.net.SocketTimeoutException -> "请求超时，请先刷新核对结果"
    is javax.net.ssl.SSLException -> "安全连接失败，请检查手机时间和网络"
    else -> e.message?.takeIf { it.length<=180 && !it.contains("http",true) && !it.contains("token",true) } ?: "操作暂未完成，请检查网络和配置后重试"
}
