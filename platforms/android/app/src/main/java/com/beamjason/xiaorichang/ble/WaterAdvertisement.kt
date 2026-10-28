package com.beamjason.xiaorichang.ble

/** Android may retain an old device name; current local-name advertising is
 * independently authoritative, as in the iPhone discovery path. Identity still
 * has to be read and checked before any water authorization. */
fun matchesWaterAdvertisement(expected:String,cached:String?,advertised:String?):Boolean =
    expected.isNotBlank() && (cached==expected || advertised==expected)
