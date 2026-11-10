package com.beamjason.xiaorichang.net

import kotlinx.coroutines.ensureActive

data class PortalDormAddress(val campus:String,val building:String,val floor:Int,val room:String,val unit:String?=null) {
    val shortRoom get()=building+"栋"+room
    fun matches(label:String,level:Int):Boolean {
        val value=label.filterNot(Char::isWhitespace)
        return when(level) {
            0->value==campus
            1->value in listOf(building+"栋",building+"幢",building+"号楼")
            2->{val cn=listOf("零","一","二","三","四","五","六","七","八","九","十","十一","十二","十三","十四","十五","十六","十七","十八","十九","二十").getOrNull(floor) ?: floor.toString();value in listOf("${floor}楼","${floor}层",cn+"楼",cn+"层")}
            3->value in listOf(room,room+"房",room+"室")
            else->false
        }
    }
    fun matchesUnit(label:String)=unit!=null && label.filterNot(Char::isWhitespace) in listOf(unit+"号",unit+"单元")
    fun powerBranchCandidates(labels:List<String>):List<String> = when {
        labels.any{Regex("[0-9]+(?:栋|幢|号楼)$").containsMatchIn(it)}->labels.filter{matches(it,1)}
        labels.any{Regex("[0-9]+(?:号|单元)$").containsMatchIn(it)}->labels.filter{matchesUnit(it)}
        labels.any{Regex("[0-9一二三四五六七八九十]+(?:楼|层)$").containsMatchIn(it)}->labels.filter{matches(it,2)}
        labels.any{Regex("^[0-9]{2,6}(?:房|室)?$").matches(it)}->labels.filter{matches(it,3)}
        else->labels
    }
    fun matchesMeterRoom(label:String)=label.filterNot{it.isWhitespace()||it=='·'} in listOf(shortRoom,shortRoom+"房",shortRoom+"室")
    fun keepsPowerBinding(selection:List<String>,savedRoom:String,meterRoom:String?):Boolean {
        if(selection.size!=4 || !selection.withIndex().all{(level,label)->matches(label,level)})return false
        if(meterRoom!=null && matchesMeterRoom(meterRoom) || matchesMeterRoom(savedRoom))return true
        val old=savedRoom.split(" · ")
        return old.size==4 && old.withIndex().all{(level,label)->matches(label,level)}
    }
    companion object {
        fun hasMoved(old:String,new:String):Boolean {
            val before=parse(old) ?: return false
            val after=parse(new) ?: return false
            return before!=after
        }
        fun parse(raw:String):PortalDormAddress? {
            val text=raw.filterNot(Char::isWhitespace);if(text.length>128)return null
            val m=Regex("^(.{1,32}校区)([A-Za-z]?[0-9]{1,3})(?:栋|幢)(?:([0-9]{1,3})号)?([0-9]{1,2})(?:层|楼)([0-9]{2,6}[A-Za-z]?)(?:房|室)$").matchEntire(text) ?: return null
            val floor=m.groupValues[4].toIntOrNull()?.takeIf{it>0} ?: return null
            return PortalDormAddress(m.groupValues[1],m.groupValues[2],floor,m.groupValues[5],m.groupValues[3].ifBlank{null})
        }
    }
}
data class CampusPowerSuggestion(val building:String,val meter:PowerMeter)

data class CampusPowerCandidate(val path:List<Option>) {
    val id get()=path.last().id
    val label get()=path.drop(1).joinToString(" · "){it.name}
}
data class CampusPowerResolution(val suggestion:CampusPowerSuggestion?=null,val choices:List<CampusPowerCandidate> = emptyList())

suspend fun discoverCampusPower(address:PortalDormAddress,readBuildings:suspend (String?)->List<Option>,readMeters:suspend (String)->List<PowerMeter>):CampusPowerResolution {
    val campus=readBuildings(null).filter{address.matches(it.name,0)}.singleOrNull() ?: return CampusPowerResolution()
    val queue=java.util.ArrayDeque<List<Option>>();queue.add(listOf(campus))
    val visited=mutableSetOf<String>();val leaves=mutableListOf<CampusPowerCandidate>()
    while(queue.isNotEmpty()) {
        kotlinx.coroutines.currentCoroutineContext().ensureActive()
        val path=queue.removeFirst();val parent=path.last().id
        if(visited.size>=64 || !visited.add(parent))return CampusPowerResolution()
        val children=readBuildings(parent)
        if(children.isEmpty()) {
            if(path.any{address.matches(it.name,1)} && path.any{address.matches(it.name,2)||address.matches(it.name,3)})leaves+=CampusPowerCandidate(path)
            continue
        }
        if(path.size>=7)return CampusPowerResolution()
        val names=address.powerBranchCandidates(children.map{it.name}).toSet()
        val next=children.filter{it.name in names}
        if(next.size>24)return CampusPowerResolution()
        next.forEach{queue.add(path+it)}
    }
    val only=leaves.singleOrNull() ?: return CampusPowerResolution(choices=leaves)
    return CampusPowerResolution(suggestion=selectCampusPower(only,address,readMeters))
}
suspend fun selectCampusPower(candidate:CampusPowerCandidate,address:PortalDormAddress,readMeters:suspend (String)->List<PowerMeter>):CampusPowerSuggestion? {
    val path=candidate.path
    if(!address.matches(path.first().name,0) || path.none{address.matches(it.name,1)})return null
    val exactRoomPath=path.any{address.matches(it.name,2)} && path.any{address.matches(it.name,3)}
    return readMeters(candidate.id).filter{address.matchesMeterRoom(it.room) || exactRoomPath && address.matches(it.room,3)}.singleOrNull()?.let{CampusPowerSuggestion(candidate.id,it)}
}
suspend fun resolveCampusPower(address:PortalDormAddress,readBuildings:suspend (String?)->List<Option>,readMeters:suspend (String)->List<PowerMeter>):CampusPowerSuggestion? =
    discoverCampusPower(address,readBuildings,readMeters).suggestion
suspend fun CampusClient.resolvePower(c:CampusConfig,address:PortalDormAddress):CampusPowerResolution =
    discoverCampusPower(address,{powerBuildings(c,it)},{powerMeters(c,it)})
suspend fun CampusClient.suggestPower(c:CampusConfig,address:PortalDormAddress):CampusPowerSuggestion? = resolvePower(c,address).suggestion

class CampusPowerMatchScope(private val config:CampusConfig) {
    fun accepts(current:CampusConfig):Boolean {
        val address=PortalDormAddress.parse(config.portalDormAddress) ?: return false
        return config.syscustid==current.syscustid && config.custid==current.custid && config.areaCode==current.areaCode && config.token==current.token &&
            config.portalDormAddress==current.portalDormAddress && config.buildingId==current.buildingId && config.meterId==current.meterId &&
            (current.dorm==config.dorm || address.matchesMeterRoom(current.dorm))
    }
}
