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
    val readIdentities:Map<String,String> = emptyMap(),val checkingAddress:String?=null,val checkingIndex:Int=0,val suggestedPower:CampusPowerSuggestion?=null,val autoMatched:Boolean=false,
    val matchingPower:Boolean=false,val serviceEnabled:Boolean?=null)
data class PowerSetup(val options:List<Option> = emptyList(),val path:List<Option> = emptyList(),val meters:List<PowerMeter> = emptyList())
data class CampusUiState(val campus:CampusConfig=CampusConfig(),val water:WaterSettings=WaterSettings(),val account:UjingAccount?=null,
    val washers:List<SavedWasher> = emptyList(),val selectedWasher:String?=null,val washer:WasherSnapshot?=null,val cache:BalanceCache=BalanceCache(),
    val cardError:String?=null,val powerError:String?=null,val washerError:String?=null,val waterSession:ShowerSession?=null,
    val checkout:CheckoutRecord?=null,val busy:Set<String> = emptySet(),val message:String?=null,val storageIssue:Boolean=false,
    val dormSetup:DormSetup=DormSetup(),val powerSetup:PowerSetup=PowerSetup(),val webSession:CampusWebSession?=null,
    val matchingPower:Boolean=false,val powerChoices:List<CampusPowerCandidate> = emptyList(),val powerMatchIssue:String?=null,
    val waterInspection:String?=null) {
    val setupCount get() = (if(campus.configured) 1 else 0)+(if(water.configured) 1 else 0)+(if(account!=null && washers.isNotEmpty()) 1 else 0)
    val unresolvedWater get() = waterSession!=null && waterSession.stage!=ShowerStage.SETTLED
    val unresolvedLaundry get() = checkout!=null && checkout.stage!=CheckoutStage.COMPLETED
    val transactionBusy get() = busy.any { it in setOf("water","verify","order","payment","cancel","orderRefresh") }
}

/** State is retained across Activity recreation; credentials and transaction markers
 * are encrypted before writes. UI never owns network calls or transaction state. */
class CampusViewModel @JvmOverloads constructor(application:Application,
    private val bundledPlatform:WaterSettings? = loadBundledWaterPlatform(application),
    private val powerDirectory:suspend (CampusConfig,PortalDormAddress)->CampusPowerResolution = {c,a->CampusClient().resolvePower(c,a)},
    private val powerMeterReader:suspend (CampusConfig,String)->List<PowerMeter> = {c,b->CampusClient().powerMeters(c,b)},
    suppliedWaterTransport:WaterTransport? = null,
    private val campusApi:CampusClient = CampusClient()):AndroidViewModel(application) {
    private val secure=SecureStore(application)
    private val laundryApi=UjingClient()
    private val transport=suppliedWaterTransport ?: BleWaterTransport(application)
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
    init { provisionBundledPlatform();provisionDevelopmentPlatform() }

    private fun provisionBundledPlatform() {
        val current=_state.value
        if(current.water.hasPlatform || current.unresolvedWater || current.storageIssue || current.transactionBusy)return
        val seed=bundledPlatform ?: return
        try {
            saveSettings(current.campus,seed)
            _state.update{it.copy(water=seed)}
        } catch(_:Exception) {notice("热水平台配置暂时无法保存，请保留现有数据并重试")}
    }

    // Developer-controlled test devices can be prepared over their authorized
    // USB connection. This is a separate legacy fallback to the bundled profile.
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
        val loadedCache=parse("campus.balance-cache",BalanceCache::read)?.takeIf { it.owner==campus.owner } ?: BalanceCache(owner=campus.owner)
        // Legacy caches lack a card owner; preserve the meter but refresh the card.
        var cache=if(loadedCache.cardOwner==campus.cardOwner)loadedCache else loadedCache.copy(card=null,cardAt=0,cardOwner=campus.cardOwner)
        if(campus.buildingId.isBlank() || campus.meterId.isNotBlank() && cache.power?.id!=campus.meterId)cache=cache.copy(power=null,powerAt=0)
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
    fun resume() { provisionBundledPlatform();provisionDevelopmentPlatform(); refresh(); matchPowerAutomatically(); if(_state.value.checkout?.orderId!=null) refreshOrder(false); selectedWasher()?.let { refreshWasher(it,false) } }
    fun refresh(force:Boolean=false) {
        val c=_state.value.campus; if(!c.configured) return
        fun due(key:String):Boolean {
            val now=System.currentTimeMillis(); if(now-(attempts[key] ?: 0)<if(force) 5_000 else 300_000) return false
            attempts[key]=now; return true
        }
        if(due("card")) action("card") {
            try {
                val value=campusApi.balance(c); if(!_state.value.campus.sameCardSession(c)) return@action
                val next=_state.value.cache.copy(card=value,cardAt=System.currentTimeMillis(),cardOwner=c.cardOwner); write("campus.balance-cache",next.json())
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
        cancelPowerMatching()
        val old=_state.value.campus
        val own=c.copy(dorm=PortalDormAddress.parse(c.portalDormAddress)?.shortRoom.orEmpty())
        val moved=PortalDormAddress.hasMoved(old.portalDormAddress,c.portalDormAddress)
        val next=if(!moved && old.syscustid==c.syscustid && old.areaCode==c.areaCode) own.copy(dorm=old.dorm.ifBlank{own.dorm},buildingId=old.buildingId,meterId=old.meterId,portalDormAddress=c.portalDormAddress.ifBlank{old.portalDormAddress}) else own
        val changed=old.syscustid!=c.syscustid || old.areaCode!=c.areaCode
        val water=if((changed || moved) && _state.value.water.access!=null) WaterSettings() else if(changed || moved) _state.value.water.copy(studentId="",schoolId="",machineId="",address=null,room="") else _state.value.water
        saveSettings(next,water)
        _state.update { it.copy(campus=next,water=water,waterInspection=null,
            cache=if(changed) BalanceCache(owner=next.owner,cardOwner=next.cardOwner) else {
                val card=if(it.cache.cardOwner!=next.cardOwner) it.cache.copy(card=null,cardAt=0,cardOwner=next.cardOwner) else it.cache
                if(moved) card.copy(power=null,powerAt=0) else card
            },cardError=null,powerError=null,webSession=null,dormSetup=DormSetup(),message="学校账号已保存") }
        attempts.clear()
        matchPowerAutomatically()
        try {ensureWaterAccess(next)}catch(e:Exception){if(e is CancellationException)throw e;notice("学校账号已保存；热水自动连接暂未完成，请在宿舍页面重试")}
        onSaved(); refresh(true)
    }
    private suspend fun ensureWaterAccess(c:CampusConfig) {
        transactionAllowed();check(!_state.value.unresolvedWater){"请先核对当前热水会话"}
        val old=_state.value.water
        if(old.hasPlatform && old.access==null)return
        val seed=bundledPlatform ?: error("当前安装包未包含热水平台配置，请更新完整版本")
        val identity=if(old.access!=null)campusApi.readDormIdentity(c,seed.platform()) else null
        val current=_state.value
        check(current.campus.sameDormSession(c)){"账号或宿舍已变化，请重新读取"}
        check(current.water==old){"热水配置已变化，请重试"}
        val next=if(identity!=null)migrateWaterToDirect(old,seed,identity,c.waterAccessOwner(),_state.value.unresolvedWater) else seed
        saveSettings(current.campus,next);_state.update{it.copy(water=next,dormSetup=DormSetup(),waterInspection=null)}
    }
    fun importConfig(text:String,platformOnly:Boolean=false) = action("import") {
        transactionAllowed(); require(text.toByteArray().size<=65536); check(!_state.value.unresolvedWater && !_state.value.transactionBusy) { "请先核对当前热水会话" }
        val w=if(platformOnly) {
            check(!_state.value.water.configured){"当前已绑定热水，请使用原有配置"}
            parseWaterPlatformImport(text)
        } else {
            val root=JSONObject(text); val raw=root.optJSONObject("water") ?: root.optJSONObject("platform") ?: root
            WaterSettings.read(raw)
        }
        require(w.hasPlatform) { "请选择热水接入文件或本人 waterconfig 文件" }
        require(w.secret.length<=256 && w.sid.length<=128 && w.bleName.length<=64)
        // Imported MAC/address is never treated as physically verified.
        val safe=w.copy(address=null)
        if(safe.machineId.isNotBlank()) safe.profile().validate()
        saveSettings(_state.value.campus,safe); _state.update { it.copy(water=safe,dormSetup=DormSetup(),waterInspection=null,message="热水配置已导入，可继续选择自己的宿舍") }
    }
    fun loadDorm() = action("dorm") {
        require(_state.value.campus.configured) { "请先登录学校账号" }
        ensureWaterAccess(_state.value.campus)
        val s=_state.value
        check(!s.unresolvedWater) { "当前有未完成热水会话，暂不能更换设备" }
        check(s.water.access==null){"请更新完整版本后重新登录学校账号"}
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
                draft=draft.copy(autoMatched=true,selected=draft.machines.singleOrNull())
            }
        }
        check(_state.value.campus.sameDormSession(s.campus) && _state.value.water==s.water) { "学校账号或宿舍已变化，请重新读取" }
        _state.update { it.copy(dormSetup=draft) }
        require(root.isNotEmpty()) { "学校未返回宿舍列表，请稍后重试" }
    }
    private var powerMatch:Job?=null
    private var powerScope:CampusPowerMatchScope?=null
    private fun cancelPowerMatching() {
        powerMatch?.cancel();powerMatch=null;powerScope=null
        _state.update{it.copy(matchingPower=false,powerChoices=emptyList(),powerMatchIssue=null)}
    }
    fun matchPowerAutomatically(retry:Boolean=false) {
        val s=_state.value;val c=s.campus
        val address=PortalDormAddress.parse(c.portalDormAddress) ?: return
        if(!c.configured || c.buildingId.isNotBlank() || s.matchingPower || s.storageIssue || (!retry && s.powerChoices.isNotEmpty()))return
        val now=System.currentTimeMillis()
        if(!retry && now-(attempts["powerMatch"] ?: 0)<300_000)return
        cancelPowerMatching();attempts["powerMatch"]=now
        val scope=CampusPowerMatchScope(c);powerScope=scope
        _state.update{it.copy(matchingPower=true)}
        powerMatch=viewModelScope.launch {
            try {
                val result=withTimeout(60_000){powerDirectory(c,address)}
                if(!scope.accepts(_state.value.campus))return@launch
                _state.update{it.copy(matchingPower=false,powerChoices=result.choices,powerMatchIssue=if(result.suggestion==null && result.choices.isEmpty())"未找到唯一电表，可手动选择位置或稍后重试。" else null)}
                result.suggestion?.let{applyAutomaticPower(it,scope)}
            } catch(e:Exception) {
                if(e is CancellationException && e !is TimeoutCancellationException)throw e
                if(scope.accepts(_state.value.campus))_state.update{it.copy(matchingPower=false,powerMatchIssue=if(e is TimeoutCancellationException)"电表匹配超时，请稍后重试。" else message(e))}
            }
        }
    }
    fun choosePowerApartment(candidate:CampusPowerCandidate) {
        val s=_state.value;val scope=powerScope ?: return
        val address=PortalDormAddress.parse(s.campus.portalDormAddress) ?: return
        if(s.matchingPower || candidate !in s.powerChoices || !scope.accepts(s.campus))return
        _state.update{it.copy(matchingPower=true,powerMatchIssue=null)}
        powerMatch=viewModelScope.launch {
            try {
                val result=withTimeout(20_000){selectCampusPower(candidate,address){powerMeterReader(s.campus,it)}}
                if(!scope.accepts(_state.value.campus))return@launch
                _state.update{it.copy(matchingPower=false)}
                if(result!=null)applyAutomaticPower(result,scope)
                else _state.update{it.copy(powerMatchIssue="该位置未返回唯一的本寝室电表，请核对公寓或手动选择。")}
            } catch(e:Exception) {
                if(e is CancellationException && e !is TimeoutCancellationException)throw e
                if(scope.accepts(_state.value.campus))_state.update{it.copy(matchingPower=false,powerMatchIssue=message(e))}
            }
        }
    }
    private fun applyAutomaticPower(power:CampusPowerSuggestion,scope:CampusPowerMatchScope) {
        val s=_state.value;if(!scope.accepts(s.campus) || s.storageIssue)return
        val c=s.campus.copy(buildingId=power.building,meterId=power.meter.id)
        val cache=s.cache.copy(owner=c.owner,power=power.meter,powerAt=System.currentTimeMillis())
        // The meter is derived from this cache. Commit the cache first so a
        // failed write cannot leave a hidden meter binding in saved settings.
        write("campus.balance-cache",cache.json());saveSettings(c,s.water)
        powerScope=null
        _state.update{it.copy(campus=c,cache=cache,matchingPower=false,powerChoices=emptyList(),powerMatchIssue=null,powerError=null)}
    }
    fun chooseDorm(option:Option,level:Int) = action("dorm") {
        val s=_state.value; check(!s.unresolvedWater); val d=s.dormSetup; val who=d.identity ?: error("请先读取本人宿舍信息")
        require(level in 0..3 && d.levels.getOrNull(level)?.contains(option)==true)
        val path=d.path.take(level)+option
        if(level==3) {
            val machines=campusApi.waterMachines(option.id,who.schoolId,s.water.platform())
            check(_state.value.campus.sameDormSession(s.campus) && _state.value.water==s.water)
            _state.update { it.copy(dormSetup=d.copy(path=path,levels=d.levels.take(4),machines=machines,selected=machines.singleOrNull(),candidates=emptyList(),verifiedAddress=null,readIdentities=emptyMap(),checkingAddress=null,suggestedPower=null,autoMatched=false,matchingPower=false)) }
            require(machines.isNotEmpty()) { "该寝室未返回水控，请重新核对房间" }
        } else {
            val next=campusApi.dormOptions(option.id,level==2,s.water.platform())
            val draft=autoSingleDorm(s,d.copy(path=path,levels=d.levels.take(level+1)+listOf(next),machines=emptyList(),selected=null,candidates=emptyList(),verifiedAddress=null,readIdentities=emptyMap(),checkingAddress=null,suggestedPower=null,autoMatched=false,matchingPower=false))
            check(_state.value.campus.sameDormSession(s.campus) && _state.value.water==s.water)
            _state.update { it.copy(dormSetup=draft) }
        }
    }
    private suspend fun autoSingleDorm(s:CampusUiState,initial:DormSetup):DormSetup {
        var d=initial
        while(d.path.size<4) {
            val level=d.path.size;val only=d.levels.getOrNull(level)?.singleOrNull() ?: break
            val path=d.path+only
            d=if(level==3) {
                val machines=campusApi.waterMachines(only.id,d.identity!!.schoolId,s.water.platform())
                d.copy(path=path,machines=machines,selected=machines.singleOrNull())
            } else d.copy(path=path,levels=d.levels+listOf(campusApi.dormOptions(only.id,level==2,s.water.platform())))
        }
        // Selection remains a draft; the user must still save the room.
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
        fun stillCurrent() = _state.value.campus.sameDormSession(s.campus) && _state.value.water==s.water && _state.value.dormSetup.selected==machine
        check(stillCurrent()){ "宿舍已变化，请重新扫描" }
        _state.update { it.copy(dormSetup=it.dormSetup.copy(candidates=found,verifiedAddress=null,readIdentities=emptyMap(),checkingAddress=null)) }
        require(found.isNotEmpty()) { "未发现水控，请靠近设备、打开蓝牙后重试" }
        try {
            for((index,candidate) in found.take(16).withIndex()) {
                check(stillCurrent()){ "宿舍已变化，请重新扫描" }
                _state.update{it.copy(dormSetup=it.dormSetup.copy(checkingAddress=candidate.address,checkingIndex=index+1))}
                val actual=try {
                    withTimeoutOrNull(12_000) {
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
            notice(if(found.size>16) "附近同名设备较多，请更靠近自己的水控后重试" else "未找到匹配的宿舍水控，请靠近设备后重试")
        } finally {_state.update{it.copy(dormSetup=it.dormSetup.copy(checkingAddress=null,checkingIndex=0))}}
    }
    fun verifyWater(candidate:BleCandidate) = action("verify") {
        val s=_state.value; check(!s.unresolvedWater && s.busy.none { it in setOf("water","order","payment","cancel","orderRefresh") }); val m=s.dormSetup.selected ?: error("请先选择学校返回的水控")
        require(candidate in s.dormSetup.candidates)
        fun stillCurrent():Boolean {
            val current=_state.value
            return !current.unresolvedWater && current.busy.none { it in setOf("water","order","payment","cancel","orderRefresh") } && current.campus.sameDormSession(s.campus) &&
                current.water==s.water && current.dormSetup.selected==m && candidate in current.dormSetup.candidates
        }
        try {
            val actual=withTimeoutOrNull(12_000) {
                transport.connect(s.water.bleName,candidate.address)
                com.beamjason.xiaorichang.core.WaterProtocol.identity(transport.exchange(byteArrayOf(0xAA.toByte())))
            } ?: error("读取水控编号超时，请靠近设备后重试")
            check(stillCurrent()) { "宿舍或水控已变化，请重新核对" }
            require(actual.equals(m.machineId,true)) { "这台蓝牙水控与所选编号不一致，请选择另一台" }
            _state.update { it.copy(dormSetup=it.dormSetup.copy(verifiedAddress=candidate.address,readIdentities=it.dormSetup.readIdentities+(candidate.address to actual)),message="已通过蓝牙读取并核对水控编号") }
        } finally { transport.disconnect() }
    }
    fun saveDorm(onSaved:()->Unit={}) = action("saveDorm") {
        transactionAllowed(); val s=_state.value; check(!s.unresolvedWater && !s.transactionBusy)
        val d=s.dormSetup; val m=d.selected ?: error("请选择自己的水控"); val who=d.identity ?: error("本人身份尚未读取")
        require(d.path.size==4); val room=d.path[1].name+d.path[3].name
        check(s.water.access==null){"请先更新热水连接"}
        val retained=previouslyVerifiedAddress(s.water,who.studentId,who.schoolId,m.machineId,room)
        val water=s.water.copy(studentId=who.studentId,schoolId=who.schoolId,machineId=m.machineId,address=d.verifiedAddress ?: retained,room=room)
        water.profile().validate()
        val address=PortalDormAddress.parse(s.campus.portalDormAddress)
        val keepPower=address?.keepsPowerBinding(d.path.map{it.name},s.campus.dorm,s.cache.power?.room)==true
        if(!keepPower)cancelPowerMatching()
        val c=s.campus.copy(dorm=room,buildingId=if(keepPower)s.campus.buildingId else "",meterId=if(keepPower)s.campus.meterId else "")
        val cache=if(keepPower)s.cache else s.cache.copy(power=null,powerAt=0)
        // Invalidate the derived cache first. If this write fails, the
        // authoritative account/dorm/controller remain unchanged. A crash
        // after it succeeds can only discard cached balances, not leave a
        // newly saved controller hidden behind stale in-memory settings.
        write("campus.balance-cache",cache.json());saveSettings(c,water)
        _state.update { it.copy(water=water,campus=c,cache=cache,waterInspection=null,message=if(water.address!=null) "宿舍和已核对水控已保存" else "宿舍已保存，首次开始时会读取并核对水控编号") }
        onSaved()
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
        cancelPowerMatching()
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
    /** Read-only identity check from the water page; no authorization or transaction. */
    fun inspectConfiguredWater() = action("verify") {
        transactionAllowed()
        val before=_state.value;val water=before.water
        check(before.busy.none{it in setOf("water","order","payment","cancel")} && !before.unresolvedWater) { "请先完成或核对当前热水会话" }
        require(water.configured) { "请先选择宿舍和水控" }
        _state.update{it.copy(waterInspection="正在查找并核对水控编号…")}
        try {
            val verified=transport.connectVerified(water.bleName,water.machineId,water.address)
            check(com.beamjason.xiaorichang.core.WaterProtocol.identity(verified.identityFrame).equals(water.machineId,true)) { "水控编号不匹配" }
            val current=_state.value
            check(current.water==water && current.campus.sameDormSession(before.campus) && !current.unresolvedWater) { "账号或宿舍已变化，请重新核对" }
            val next=water.copy(address=verified.address)
            saveSettings(current.campus,next)
            _state.update{it.copy(water=next,waterInspection="已找到本宿舍水控，编号已核对。")}
        } catch(e:CancellationException){throw e}
          catch(e:Exception){_state.update{it.copy(waterInspection=message(e))};throw e}
        finally {transport.disconnect()}
    }
    fun operateWater(finish:Boolean) = action("water") {
        transactionAllowed(); check(!_state.value.busy.contains("verify"))
        if(!finish && _state.value.water.access!=null)ensureWaterAccess(_state.value.campus)
        val w=_state.value.water; require(w.configured) { "请先选择宿舍和水控" }
        check(w.access==null){"请登录学校账号并重新匹配宿舍，更新热水连接"}
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
