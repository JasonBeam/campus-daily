package com.beamjason.xiaorichang

import com.beamjason.xiaorichang.ui.GlassMode
import com.beamjason.xiaorichang.ui.resolveGlassMode
import org.junit.Assert.assertEquals
import org.junit.Test

class GlassPolicyTest {
    @Test fun capabilitiesNeverEnableUnsupportedShaders() {
        for(sdk in 23..30)assertEquals(GlassMode.SOLID,resolveGlassMode(sdk,true,false,false))
        for(sdk in 31..32)assertEquals(GlassMode.FROSTED,resolveGlassMode(sdk,true,false,false))
        for(sdk in 33..36)assertEquals(GlassMode.LIQUID,resolveGlassMode(sdk,true,false,false))
    }
    @Test fun accessibilityToSimpleRenderingTakesPriority() {
        for(sdk in 23..36){
            assertEquals(GlassMode.SOLID,resolveGlassMode(sdk,false,false,false))
            assertEquals(GlassMode.SOLID,resolveGlassMode(sdk,true,true,false))
            assertEquals(GlassMode.SOLID,resolveGlassMode(sdk,true,false,true))
        }
    }
}
