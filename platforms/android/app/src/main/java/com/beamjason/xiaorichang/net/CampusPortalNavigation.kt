package com.beamjason.xiaorichang.net

import java.net.URI

/** The school's root document only selects a supported browser then sends the
 * unchanged raw query to main.html. Keep CAS service/ticket encoding intact. */
fun campusPortalDocument(url:String):String? = runCatching {
    if(url.length>16384)return null
    val uri=URI(url)
    if(!uri.scheme.equals("https",true) || !uri.host.equals("portal.gdbtu.edu.cn",true) ||
        uri.rawUserInfo!=null || uri.port !in listOf(-1,443) || uri.rawPath !in listOf("","/"))return null
    "https://${uri.rawAuthority}/main.html"+
        (uri.rawQuery?.let{"?$it"} ?: "")+(uri.rawFragment?.let{"#$it"} ?: "")
}.getOrNull()
