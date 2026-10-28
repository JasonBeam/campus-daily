package com.beamjason.xiaorichang.net

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
    companion object {
        fun parse(raw:String):PortalDormAddress? {
            val text=raw.filterNot(Char::isWhitespace);if(text.length>128)return null
            val m=Regex("^(.{1,32}校区)([A-Za-z]?[0-9]{1,3})(?:栋|幢)(?:([0-9]{1,3})号)?([0-9]{1,2})(?:层|楼)([0-9]{2,6}[A-Za-z]?)(?:房|室)$").matchEntire(text) ?: return null
            val floor=m.groupValues[4].toIntOrNull()?.takeIf{it>0} ?: return null
            return PortalDormAddress(m.groupValues[1],m.groupValues[2],floor,m.groupValues[5],m.groupValues[3].ifBlank{null})
        }
    }
}
data class CampusPowerSuggestion(val building:String,val meter:PowerMeter)

suspend fun resolveCampusPower(address:PortalDormAddress,readBuildings:suspend (String?)->List<Option>,readMeters:suspend (String)->List<PowerMeter>):CampusPowerSuggestion? {
    val campus=readBuildings(null).filter{address.matches(it.name,0)}.singleOrNull() ?: return null
    val queue=java.util.ArrayDeque<Pair<String,Int>>();queue.add(campus.id to 0)
    var visits=0;val matches=mutableListOf<CampusPowerSuggestion>()
    while(queue.isNotEmpty() && visits++<32) {
        val (parent,depth)=queue.removeFirst();val children=readBuildings(parent)
        if(children.isEmpty()) {
            matches+=readMeters(parent).filter{address.matchesMeterRoom(it.room)}.map{CampusPowerSuggestion(parent,it)}
            if(matches.size>1)return null
            continue
        }
        if(depth>=5)return null
        val names=address.powerBranchCandidates(children.map{it.name}).toSet()
        val next=children.filter{it.name in names}
        if(next.size>12)return null
        next.forEach{queue.add(it.id to depth+1)}
    }
    return if(queue.isEmpty())matches.singleOrNull() else null
}

suspend fun CampusClient.suggestPower(c:CampusConfig,address:PortalDormAddress):CampusPowerSuggestion? =
    resolveCampusPower(address,{powerBuildings(c,it)},{powerMeters(c,it)})
