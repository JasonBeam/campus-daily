#!/usr/bin/env python3
"""Generate a dependency-free Xcode project; identities stay in local build flags."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[1]
project = root / 'CampusHotWater.xcodeproj'
project.mkdir(exist_ok=True)
def uid(name): return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
objects = []
def obj(name, body):
    key = uid(name)
    objects.append(f'{key} = {{ {body} }};')
    return key
sources = []
refs = []
for path in sorted((root / 'App').glob('*.swift')):
    ref = obj('ref:'+path.name, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = App/{path.name}; sourceTree = "<group>";')
    refs.append(ref)
    sources.append(obj('build:'+path.name, f'isa = PBXBuildFile; fileRef = {ref};'))
for path in sorted((root / 'Shared').glob('*.swift')):
    ref = obj('shared-ref:'+path.name, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Shared/{path.name}; sourceTree = "<group>";')
    refs.append(ref)
    sources.append(obj('shared-build:'+path.name, f'isa = PBXBuildFile; fileRef = {ref};'))
product = obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = CampusHotWater.app; sourceTree = BUILT_PRODUCTS_DIR;')
products = obj('products', f'isa = PBXGroup; children = ({product}); name = Products; sourceTree = "<group>";')
group = obj('group', f'isa = PBXGroup; children = ({",".join(refs + [products])}); sourceTree = "<group>";')
package = obj('package', 'isa = XCLocalSwiftPackageReference; relativePath = .;')
dependency = obj('dependency', f'isa = XCSwiftPackageProductDependency; package = {package}; productName = WaterCore;')
framework = obj('framework', f'isa = PBXBuildFile; productRef = {dependency};')
srcphase = obj('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(sources)}); runOnlyForDeploymentPostprocessing = 0;')
sdkref = obj('alipay-sdk-ref', 'isa = PBXFileReference; lastKnownFileType = wrapper.xcframework; path = "Vendor/AlipaySDK-15.8.30/AlipaySDK.xcframework"; sourceTree = SOURCE_ROOT;')
sdkbuild = obj('alipay-sdk-build', f'isa = PBXBuildFile; fileRef = {sdkref};')
systembuilds = []
for name in ['UIKit','Foundation','CFNetwork','SystemConfiguration','QuartzCore','CoreGraphics','CoreMotion','CoreTelephony','CoreText','WebKit']:
    ref = obj('system:'+name, f'isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = {name}.framework; path = System/Library/Frameworks/{name}.framework; sourceTree = SDKROOT;')
    systembuilds.append(obj('system-build:'+name, f'isa = PBXBuildFile; fileRef = {ref};'))
fwphase = obj('frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({framework},{sdkbuild},{",".join(systembuilds)}); runOnlyForDeploymentPostprocessing = 0;')
assetref = obj('assetref', 'isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = App/Assets.xcassets; sourceTree = SOURCE_ROOT;')
assetbuild = obj('assetbuild', f'isa = PBXBuildFile; fileRef = {assetref};')
sdkresources = obj('alipay-resource-ref', 'isa = PBXFileReference; lastKnownFileType = wrapper.plug-in; path = "Vendor/AlipaySDK-15.8.30/AlipaySDK.bundle"; sourceTree = SOURCE_ROOT;')
sdkresourcebuild = obj('alipay-resource-build', f'isa = PBXBuildFile; fileRef = {sdkresources};')
fontref = obj('nothing-fonts-ref', 'isa = PBXFileReference; lastKnownFileType = folder; path = App/Fonts; sourceTree = SOURCE_ROOT;')
fontbuild = obj('nothing-fonts-build', f'isa = PBXBuildFile; fileRef = {fontref};')
automationref = obj('campus-login-automation-ref', 'isa = PBXFileReference; lastKnownFileType = sourcecode.javascript; path = Shared/CampusLoginAutomation.js; sourceTree = SOURCE_ROOT;')
automationbuild = obj('campus-login-automation-build', f'isa = PBXBuildFile; fileRef = {automationref};')
extra_resources = [fontbuild, automationbuild]
profile = root / 'private/distribution/WaterPlatformProfile.json'
resource_files = [assetbuild, sdkresourcebuild] + extra_resources
resphase = obj('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(resource_files)}); runOnlyForDeploymentPostprocessing = 0;')
profile_script = 'python3 "$SRCROOT/tools/stage_platform_profile.py" --profile "$CAMPUS_WATER_PROFILE_PATH" --output "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/CampusWaterPlatform.json"\n'
profilephase = obj('bundled-water-platform', f'''isa = PBXShellScriptBuildPhase; buildActionMask = 2147483647; files = ();
    inputPaths = ("$(CAMPUS_WATER_PROFILE_PATH)", "$(SRCROOT)/tools/stage_platform_profile.py");
    name = "Stage shared water platform";
    outputPaths = ("$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/CampusWaterPlatform.json");
    runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/sh;
    shellScript = {json.dumps(profile_script)};''')
project_configs = []
target_configs = []
for mode in ('Debug','Release'):
    project_configs.append(obj('project:'+mode, 'isa = XCBuildConfiguration; name = '+mode+'; buildSettings = { CLANG_ENABLE_MODULES = YES; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SDKROOT = iphoneos; SWIFT_VERSION = 5.0; };'))
    settings = '''PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = com.beamjason.campushotwater;
    CODE_SIGN_STYLE = Automatic; CODE_SIGN_ENTITLEMENTS = App/Campus.entitlements; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_FILE = App/Info.plist;
    OTHER_LDFLAGS = ("$(inherited)", "-ObjC", "-lc++", "-lz");
    INFOPLIST_KEY_CFBundleDisplayName = "校日常";
    INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription = "连接你选择的校园水控，完成授权和结束结算。";
    INFOPLIST_KEY_NSCameraUsageDescription = "扫描洗衣机机身二维码，保存你的常用机器。";
    INFOPLIST_KEY_UILaunchScreen_Generation = YES; INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
    INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;
    INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace = YES;
    TARGETED_DEVICE_FAMILY = 1; MARKETING_VERSION = 0.8.0; CURRENT_PROJECT_VERSION = 38;
    ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
    SWIFT_EMIT_LOC_STRINGS = YES; ENABLE_PREVIEWS = YES;
    LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
    '''
    settings += 'SWIFT_OPTIMIZATION_LEVEL = '+('"-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if mode == 'Debug' else '"-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";')
    target_configs.append(obj('target:'+mode, f'isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ {settings} }};'))
pc = obj('project-configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(project_configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
tc = obj('target-configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(target_configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
widget_sources = []
for folder in ['Widget','Shared']:
    for path in sorted((root / folder).glob('*.swift')):
        ref = obj('widget-ref:'+path.name, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {folder}/{path.name}; sourceTree = SOURCE_ROOT;')
        widget_sources.append(obj('widget-build:'+path.name, f'isa = PBXBuildFile; fileRef = {ref};'))
widget_source_phase = obj('widget-sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(widget_sources)}); runOnlyForDeploymentPostprocessing = 0;')
widget_dep = obj('widget-core-dependency', f'isa = XCSwiftPackageProductDependency; package = {package}; productName = WaterCore;')
widget_core_build = obj('widget-core-build', f'isa = PBXBuildFile; productRef = {widget_dep};')
widget_framework_phase = obj('widget-frameworks', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = ({widget_core_build}); runOnlyForDeploymentPostprocessing = 0;')
widget_font_build = obj('widget-font-build', f'isa = PBXBuildFile; fileRef = {fontref};')
widget_resources = obj('widget-resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({widget_font_build}); runOnlyForDeploymentPostprocessing = 0;')
widget_product = obj('widget-product', 'isa = PBXFileReference; explicitFileType = wrapper.app-extension; path = CampusDailyWidget.appex; sourceTree = BUILT_PRODUCTS_DIR;')
widget_configs = []
for mode in ['Debug','Release']:
    settings = f"""PRODUCT_NAME = CampusDailyWidget; PRODUCT_BUNDLE_IDENTIFIER = com.beamjason.campushotwater.balances;
    CODE_SIGN_STYLE = Automatic; CODE_SIGN_ENTITLEMENTS = Widget/Campus.entitlements;
    GENERATE_INFOPLIST_FILE = YES; INFOPLIST_FILE = Widget/Info.plist;
    INFOPLIST_KEY_CFBundleDisplayName = \"校园双余额\";
    IPHONEOS_DEPLOYMENT_TARGET = 17.0; SDKROOT = iphoneos; SWIFT_VERSION = 5.0;
    TARGETED_DEVICE_FAMILY = 1; APPLICATION_EXTENSION_API_ONLY = YES; SKIP_INSTALL = YES;
    MARKETING_VERSION = 0.8.0; CURRENT_PROJECT_VERSION = 38;
    LD_RUNPATH_SEARCH_PATHS = (\"$(inherited)\",\"@executable_path/Frameworks\",\"@executable_path/../../Frameworks\");
    SWIFT_OPTIMIZATION_LEVEL = \"{'-Onone' if mode == 'Debug' else '-O'}\";
    """
    widget_configs.append(obj('widget-config:'+mode, f'isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ {settings} }};'))
widget_config_list = obj('widget-configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(widget_configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
widget_target = obj('widget-target', f'isa = PBXNativeTarget; buildConfigurationList = {widget_config_list}; buildPhases = ({widget_source_phase},{widget_framework_phase},{widget_resources}); buildRules = (); dependencies = (); name = CampusDailyWidget; packageProductDependencies = ({widget_dep}); productName = CampusDailyWidget; productReference = {widget_product}; productType = "com.apple.product-type.app-extension";')
widget_target_dep = obj('widget-target-dep', f'isa = PBXTargetDependency; target = {widget_target};')
widget_embed_build = obj('widget-embed-build', f'isa = PBXBuildFile; fileRef = {widget_product}; settings = {{ ATTRIBUTES = (RemoveHeadersOnCopy); }};')
widget_embed = obj('widget-embed', f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = ({widget_embed_build}); name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0;')
target = obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {tc}; buildPhases = ({srcphase},{fwphase},{resphase},{profilephase},{widget_embed}); buildRules = (); dependencies = ({widget_target_dep}); name = CampusHotWater; packageProductDependencies = ({dependency}); productName = CampusHotWater; productReference = {product}; productType = "com.apple.product-type.application";')
main = obj('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; }}; buildConfigurationList = {pc}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh-Hans; hasScannedForEncodings = 0; knownRegions = ("zh-Hans",en,Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; packageReferences = ({package}); targets = ({target},{widget_target});')
(project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {main}; }}\n')
schemes = project / 'xcshareddata/xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
(schemes / 'CampusHotWater.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="CampusHotWater.app" BlueprintName="CampusHotWater" ReferencedContainer="container:CampusHotWater.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="CampusHotWater.app" BlueprintName="CampusHotWater" ReferencedContainer="container:CampusHotWater.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release"/><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated CampusHotWater.xcodeproj (no signing identity embedded)')
