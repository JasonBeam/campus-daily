package com.beamjason.xiaorichang

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.beamjason.xiaorichang.ble.ShowerSession
import com.beamjason.xiaorichang.ble.ShowerStage
import com.beamjason.xiaorichang.ui.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WaterInspectionUiTest {
    @Test fun persistedMismatchShowsReviewAndReadOnlyInspectionDoesNotStartWater() {
        var reads=0;var starts=0
        val s=previewFixture().copy(waterSession=ShowerSession(ShowerStage.ACTIVE,"AABBCCDD","fixture-address",stateReviewRequired=true))
        compose.setContent {NativeTheme {WaterScreen(s,PaddingValues(),{},review={reads++},operate={starts++})}}
        compose.onNodeWithText("本次待核对").assertExists()
        compose.onNodeWithText("连接检查与设备信息").performScrollTo().performClick()
        compose.onNodeWithText("只读检查本次水控状态").performScrollTo().performClick()
        assertEquals(1,reads);assertEquals(0,starts)
    }
    @get:Rule val compose=createComposeRule()
    @Test fun inspectionWorksOnWaterPageWithoutNavigatingOrStartingWater() {
        val s=previewFixture().copy(waterSession=null);var inspections=0;var starts=0;var destinations=0
        compose.setContent {NativeTheme {WaterScreen(s,PaddingValues(),{destinations++},inspect={inspections++},operate={starts++})}}
        compose.onNodeWithText("连接检查与设备信息").performScrollTo().performClick()
        compose.onNodeWithText("扫描并核对本宿舍水控").performScrollTo().assertIsDisplayed().performClick()
        assertEquals(1,inspections);assertEquals(0,starts);assertEquals(0,destinations)
        compose.onNodeWithText("只读取设备编号，不会出水。").assertExists()
    }
    @Test fun inspectionIsDisabledWhileAHotWaterSessionIsUnresolved() {
        val fixture=previewFixture()
        val s=fixture.copy(waterSession=ShowerSession(ShowerStage.ACTIVE,"AABBCCDD","fixture-address"))
        compose.setContent {NativeTheme {WaterScreen(s,PaddingValues(),{},inspect={},operate={})}}
        compose.onNodeWithText("连接检查与设备信息").performScrollTo().performClick()
        compose.onNodeWithText("扫描并核对本宿舍水控").assertIsNotEnabled()
    }
    @Test fun inspectionRemainsReachableOnNarrowScreenWithLargeText() {
        val s=previewFixture().copy(waterSession=null)
        compose.setContent {
            val pixels=LocalDensity.current.density
            CompositionLocalProvider(LocalDensity provides Density(pixels,1.6f)) {
                NativeTheme {Box(Modifier.width(360.dp).fillMaxHeight()) {WaterScreen(s,PaddingValues(),{},inspect={},operate={})}}
            }
        }
        compose.onNodeWithText("连接检查与设备信息").performScrollTo().performClick()
        val inspection=compose.onNodeWithText("扫描并核对本宿舍水控").performScrollTo().assertIsDisplayed().fetchSemanticsNode().boundsInRoot
        val start=compose.onNodeWithText("开始洗澡").fetchSemanticsNode().boundsInRoot
        assertTrue("The inspection control must not be hidden behind the fixed action",inspection.bottom<=start.top)
    }
}
