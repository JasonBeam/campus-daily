package com.beamjason.xiaorichang

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.beamjason.xiaorichang.ble.BleCandidate
import com.beamjason.xiaorichang.ui.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DormScanVisibilityTest {
    @get:Rule val compose=createComposeRule()
    @Test fun firstTimeControllerSearchIsEnabledAndInvokesOnlyScan() {
        val fixture=matchedDormFixture();var scanned=0;var saved=0
        compose.setContent {NativeTheme {DormSetupContent(fixture,PaddingValues(),DormActions(save={saved++}),requestScan={scanned++})}}
        compose.onNodeWithText("查找本宿舍水控").performScrollTo().assertIsDisplayed().assertIsEnabled().performClick()
        assertEquals(1,scanned);assertEquals(0,saved)
    }
    @Test fun scanProgressShowsBoundedCountAndDisablesRepeatSearch() {
        val fixture=matchedDormFixture()
        val candidates=(1..20).map{BleCandidate("fixture-$it","fixture",-40)}
        val scanning=fixture.copy(busy=setOf("verify"),dormSetup=fixture.dormSetup.copy(candidates=candidates,checkingAddress="fixture-3",checkingIndex=3))
        compose.setContent {NativeTheme {DormSetupContent(scanning,PaddingValues(),DormActions())}}
        compose.onNodeWithText("正在核对附近设备 3/16，请保持靠近水控…").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("查找本宿舍水控").performScrollTo().assertIsNotEnabled()
    }
    @Test fun priorVerifiedDeviceIsExplainedWithoutClaimingANewScan() {
        val fixture=matchedDormFixture()
        val saved=fixture.copy(water=fixture.water.copy(machineId="AABBCCDD",address="AA:BB:CC:DD:EE:FF"))
        compose.setContent {NativeTheme {DormSetupContent(saved,PaddingValues(),DormActions())}}
        compose.onNodeWithText("已保留上次核对记录；连接时会再次核对编号。").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("保存并保留上次核对").performScrollTo().assertIsEnabled()
        compose.onNodeWithText("本宿舍水控").assertDoesNotExist()
    }
}
