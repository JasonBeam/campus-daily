package com.beamjason.xiaorichang.data

/** Cache cooldown starts only after an accepted successful read, never after a failed attempt. */
class CampusRefreshSchedule(private val now:()->Long=System::currentTimeMillis) {
    private val successes=mutableMapOf<String,Long>()
    fun due(key:String,force:Boolean=false):Boolean {
        val stamp=successes[key] ?: return true
        val elapsed=now()-stamp
        return force || elapsed<0 || elapsed>=300_000
    }
    fun succeeded(key:String){successes[key]=now()}
    fun clear(){successes.clear()}
}
