#!/usr/bin/env python3
"""Generate a dependency-free Xcode project; identities stay in local build flags."""
from pathlib import Path
import hashlib

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
extra_resources = []
profile = root / 'private/distribution/WaterPlatformProfile.json'
resource_files = [assetbuild, sdkresourcebuild] + extra_resources
resphase = obj('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({",".join(resource_files)}); runOnlyForDeploymentPostprocessing = 0;')
profilephase = obj('private-water-profile-debug-only', '''isa = PBXShellScriptBuildPhase; buildActionMask = 2147483647; files = ();
    inputPaths = ("$(SRCROOT)/private/distribution/WaterPlatformProfile.json");
    name = "Development-only private water profile";
    outputPaths = ("$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/WaterPlatformProfile.json");
    runOnlyForDeploymentPostprocessing = 0; shellPath = /bin/sh;
    shellScript = "if [ \\\"$CONFIGURATION\\\" = \\\"Debug\\\" ] && [ -f \\\"$SRCROOT/private/distribution/WaterPlatformProfile.json\\\" ]; then\\n  mkdir -p \\\"$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH\\\"\\n  cp \\\"$SRCROOT/private/distribution/WaterPlatformProfile.json\\\" \\\"$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/WaterPlatformProfile.json\\\"\\n  echo \\\"WARNING: private WaterPlatformProfile is embedded in this DEBUG app. Do not distribute it.\\\"\\nfi\\n";''')
project_configs = []
target_configs = []
for mode in ('Debug','Release'):
    project_configs.append(obj('project:'+mode, 'isa = XCBuildConfiguration; name = '+mode+'; buildSettings = { CLANG_ENABLE_MODULES = YES; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SDKROOT = iphoneos; SWIFT_VERSION = 5.0; };'))
    settings = '''PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = com.beamjason.campushotwater;
    CODE_SIGN_STYLE = Automatic; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_FILE = App/Info.plist;
    OTHER_LDFLAGS = ("$(inherited)", "-ObjC", "-lc++", "-lz");
    INFOPLIST_KEY_CFBundleDisplayName = "校日常";
    INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription = "连接你选择的校园水控，完成授权和结束结算。";
    INFOPLIST_KEY_NSCameraUsageDescription = "扫描洗衣机机身二维码，保存你的常用机器。";
    INFOPLIST_KEY_UILaunchScreen_Generation = YES; INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
    INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;
    INFOPLIST_KEY_LSSupportsOpeningDocumentsInPlace = YES;
    TARGETED_DEVICE_FAMILY = 1; MARKETING_VERSION = 0.7.0; CURRENT_PROJECT_VERSION = 22;
    ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
    SWIFT_EMIT_LOC_STRINGS = YES; ENABLE_PREVIEWS = YES;
    LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";
    '''
    settings += 'SWIFT_OPTIMIZATION_LEVEL = '+('"-Onone"; DEBUG_INFORMATION_FORMAT = dwarf; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if mode == 'Debug' else '"-O"; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";')
    target_configs.append(obj('target:'+mode, f'isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ {settings} }};'))
pc = obj('project-configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(project_configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
tc = obj('target-configs', f'isa = XCConfigurationList; buildConfigurations = ({",".join(target_configs)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target = obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {tc}; buildPhases = ({srcphase},{fwphase},{resphase},{profilephase}); buildRules = (); dependencies = (); name = CampusHotWater; packageProductDependencies = ({dependency}); productName = CampusHotWater; productReference = {product}; productType = "com.apple.product-type.application";')
main = obj('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; }}; buildConfigurationList = {pc}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh-Hans; hasScannedForEncodings = 0; knownRegions = ("zh-Hans",en,Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; packageReferences = ({package}); targets = ({target});')
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
