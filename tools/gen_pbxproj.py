#!/usr/bin/env python3
"""生成 Gerenzhuli.xcodeproj/project.pbxproj 与 xcscheme。增删文件后重新运行。

用法: python3 tools/gen_pbxproj.py   (在 gerenzhuli/ 目录下运行)
结构与定格的 tools/gen_pbxproj.py 一致，只换了 App 名、文件清单与 Bundle ID。
"""
import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = "Gerenzhuli"

SWIFT_FILES = [
    "GerenzhuliApp.swift",
    "Theme.swift",
    "Models.swift",
    "Store.swift",
    "Components.swift",
    "OnboardingView.swift",
    "PermissionsService.swift",
    "MainTabView.swift",
    "HomeView.swift",
    "CalendarView.swift",
    "RemindersView.swift",
    "SubscribersView.swift",
    "TravelView.swift",
    "BriefingView.swift",
    "VoiceInputService.swift",
    "VoiceInputView.swift",
    "LLMService.swift",
    "SettingsView.swift",
]

RESOURCE_FILES = [
    ("Assets.xcassets", "folder.assetcatalog"),
    ("PrivacyInfo.xcprivacy", "text.plist.xml"),
]

OTHER_FILES = [
    ("Info.plist", "text.plist.xml"),
    ("Gerenzhuli.entitlements", "text.plist.entitlements"),
]

# 增删文件后先校验，避免生成引用了不存在文件的工程。
missing = [f for f in SWIFT_FILES if not os.path.exists(os.path.join(ROOT, APP, f))]
missing += [f for f, _ in RESOURCE_FILES + OTHER_FILES if not os.path.exists(os.path.join(ROOT, APP, f))]
if missing:
    print("缺少文件，停止生成：", ", ".join(missing), file=sys.stderr)
    sys.exit(1)


def uid(name: str) -> str:
    return hashlib.sha1(name.encode()).hexdigest()[:24].upper()


# ---------- 固定 UUID ----------
P = {
    "project": uid("PBXProject:Gerenzhuli"),
    "main_group": uid("PBXGroup:main"),
    "app_group": uid("PBXGroup:Gerenzhuli"),
    "products_group": uid("PBXGroup:Products"),
    "target": uid("PBXNativeTarget:Gerenzhuli"),
    "product_ref": uid("PBXFileReference:Gerenzhuli.app"),
    "sources_phase": uid("PBXSourcesBuildPhase"),
    "frameworks_phase": uid("PBXFrameworksBuildPhase"),
    "resources_phase": uid("PBXResourcesBuildPhase"),
    "project_config_list": uid("XCConfigurationList:project"),
    "target_config_list": uid("XCConfigurationList:target"),
    "project_debug": uid("XCBuildConfiguration:project:Debug"),
    "project_release": uid("XCBuildConfiguration:project:Release"),
    "target_debug": uid("XCBuildConfiguration:target:Debug"),
    "target_release": uid("XCBuildConfiguration:target:Release"),
}

build_files = {f: uid(f"PBXBuildFile:src:{f}") for f in SWIFT_FILES}
res_build_files = {f: uid(f"PBXBuildFile:res:{f}") for f, _ in RESOURCE_FILES}
file_refs = {}
for f in SWIFT_FILES:
    file_refs[f] = uid(f"PBXFileReference:{f}")
for f, _ in RESOURCE_FILES + OTHER_FILES:
    file_refs[f] = uid(f"PBXFileReference:{f}")

out = []
A = out.append


def section(name):
    A(f"\n/* Begin {name} section */")


def endsection(name):
    A(f"/* End {name} section */")


A("// !$*UTF8*$!")
A("{")
A("\tarchiveVersion = 1;")
A("\tclasses = {")
A("\t};")
A("\tobjectVersion = 77;")
A("\tobjects = {")

# ---------- PBXBuildFile ----------
section("PBXBuildFile")
for f in SWIFT_FILES:
    A(f"\t\t{build_files[f]} = {{isa = PBXBuildFile; fileRef = {file_refs[f]}; }};")
for f, _ in RESOURCE_FILES:
    A(f"\t\t{res_build_files[f]} = {{isa = PBXBuildFile; fileRef = {file_refs[f]}; }};")
endsection("PBXBuildFile")

# ---------- PBXFileReference ----------
section("PBXFileReference")
A(f"\t\t{P['product_ref']} = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {APP}.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
for f in SWIFT_FILES:
    A(f"\t\t{file_refs[f]} = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {f}; sourceTree = \"<group>\"; }};")
for f, t in RESOURCE_FILES + OTHER_FILES:
    A(f"\t\t{file_refs[f]} = {{isa = PBXFileReference; lastKnownFileType = {t}; path = {f}; sourceTree = \"<group>\"; }};")
endsection("PBXFileReference")

# ---------- PBXFrameworksBuildPhase ----------
section("PBXFrameworksBuildPhase")
A(f"\t\t{P['frameworks_phase']} = {{")
A("\t\t\tisa = PBXFrameworksBuildPhase;")
A("\t\t\tbuildActionMask = 2147483647;")
A("\t\t\tfiles = (")
A("\t\t\t);")
A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
A("\t\t};")
endsection("PBXFrameworksBuildPhase")

# ---------- PBXGroup ----------
section("PBXGroup")
children = ",\n".join(f"\t\t\t\t{file_refs[f]}" for f in SWIFT_FILES + [f for f, _ in RESOURCE_FILES + OTHER_FILES])
A(f"\t\t{P['main_group']} = {{")
A("\t\t\tisa = PBXGroup;")
A("\t\t\tchildren = (")
A(f"\t\t\t\t{P['app_group']},")
A(f"\t\t\t\t{P['products_group']},")
A("\t\t\t);")
A("\t\t\tsourceTree = \"<group>\";")
A("\t\t};")
A(f"\t\t{P['app_group']} = {{")
A("\t\t\tisa = PBXGroup;")
A("\t\t\tchildren = (")
A(children + ",")
A("\t\t\t);")
A(f"\t\t\tpath = {APP};")
A("\t\t\tsourceTree = \"<group>\";")
A("\t\t};")
A(f"\t\t{P['products_group']} = {{")
A("\t\t\tisa = PBXGroup;")
A("\t\t\tchildren = (")
A(f"\t\t\t\t{P['product_ref']},")
A("\t\t\t);")
A('\t\t\tname = Products;')
A("\t\t\tsourceTree = \"<group>\";")
A("\t\t};")
endsection("PBXGroup")

# ---------- PBXNativeTarget ----------
section("PBXNativeTarget")
A(f"\t\t{P['target']} = {{")
A("\t\t\tisa = PBXNativeTarget;")
A(f"\t\t\tbuildConfigurationList = {P['target_config_list']};")
A("\t\t\tbuildPhases = (")
A(f"\t\t\t\t{P['sources_phase']},")
A(f"\t\t\t\t{P['frameworks_phase']},")
A(f"\t\t\t\t{P['resources_phase']},")
A("\t\t\t);")
A("\t\t\tbuildRules = (")
A("\t\t\t);")
A("\t\t\tdependencies = (")
A("\t\t\t);")
A('\t\t\tname = Gerenzhuli;')
A(f"\t\t\tproductName = {APP};")
A(f"\t\t\tproductReference = {P['product_ref']};")
A("\t\t\tproductType = \"com.apple.product-type.application\";")
A("\t\t};")
endsection("PBXNativeTarget")

# ---------- PBXProject ----------
section("PBXProject")
A(f"\t\t{P['project']} = {{")
A("\t\t\tisa = PBXProject;")
A("\t\t\tattributes = {")
A("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
A("\t\t\t\tLastUpgradeCheck = 1600;")
A("\t\t\t\tTargetAttributes = {")
A(f"\t\t\t\t\t{P['target']} = {{")
A("\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;")
A("\t\t\t\t\t};")
A("\t\t\t\t};")
A("\t\t\t};")
A(f"\t\t\tbuildConfigurationList = {P['project_config_list']};")
A("\t\t\tcompatibilityVersion = \"Xcode 16.0\";")
A("\t\t\tdevelopmentRegion = en;")
A("\t\t\thasScannedForEncodings = 0;")
A("\t\t\tknownRegions = (")
A("\t\t\t\ten,")
A("\t\t\t\tBase,")
A("\t\t\t);")
A(f"\t\t\tmainGroup = {P['main_group']};")
A("\t\t\tproductRefGroup = " + P["products_group"] + ";")
A("\t\t\tprojectDirPath = \"\";")
A("\t\t\tprojectRoot = \"\";")
A("\t\t\ttargets = (")
A(f"\t\t\t\t{P['target']},")
A("\t\t\t);")
A("\t\t};")
endsection("PBXProject")

# ---------- PBXResourcesBuildPhase ----------
section("PBXResourcesBuildPhase")
A(f"\t\t{P['resources_phase']} = {{")
A("\t\t\tisa = PBXResourcesBuildPhase;")
A("\t\t\tbuildActionMask = 2147483647;")
A("\t\t\tfiles = (")
for f, _ in RESOURCE_FILES:
    A(f"\t\t\t\t{res_build_files[f]},")
A("\t\t\t);")
A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
A("\t\t};")
endsection("PBXResourcesBuildPhase")

# ---------- PBXSourcesBuildPhase ----------
section("PBXSourcesBuildPhase")
A(f"\t\t{P['sources_phase']} = {{")
A("\t\t\tisa = PBXSourcesBuildPhase;")
A("\t\t\tbuildActionMask = 2147483647;")
A("\t\t\tfiles = (")
for f in SWIFT_FILES:
    A(f"\t\t\t\t{build_files[f]},")
A("\t\t\t);")
A("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
A("\t\t};")
endsection("PBXSourcesBuildPhase")

# ---------- XCBuildConfiguration ----------
section("XCBuildConfiguration")


def config(uid_, name, settings):
    A(f"\t\t{uid_} = {{")
    A("\t\t\tisa = XCBuildConfiguration;")
    A("\t\t\tbuildSettings = {")
    for k, v in settings.items():
        A(f"\t\t\t\t{k} = {v};")
    A("\t\t\t};")
    A(f"\t\t\tname = {name};")
    A("\t\t};")


project_debug = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_CXX_LANGUAGE_STANDARD": '"gnu++20"',
    "CLANG_ENABLE_MODULES": "YES",
    "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SDKROOT": "iphoneos",
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
    "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
}
project_release = dict(project_debug)
project_release.update({
    "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "ONLY_ACTIVE_ARCH": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": '"-O"',
})
project_release.pop("SWIFT_ACTIVE_COMPILATION_CONDITIONS", None)

target_base = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "CLANG_ENABLE_MODULES": "YES",
    "CODE_SIGN_ENTITLEMENTS": f'"{APP}/{APP}.entitlements"',
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": '""',
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": f'"{APP}/Info.plist"',
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks")',
    "MARKETING_VERSION": "1.0.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.lidawang.gerenzhuli",
    "PRODUCT_NAME": '"$(TARGET_NAME)"',
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1",
}
target_debug = dict(target_base)
target_release = dict(target_base)

config(P["project_debug"], "Debug", project_debug)
config(P["project_release"], "Release", project_release)
config(P["target_debug"], "Debug", target_debug)
config(P["target_release"], "Release", target_release)
endsection("XCBuildConfiguration")

# ---------- XCConfigurationList ----------
section("XCConfigurationList")
for list_id, dbg, rel in [
    (P["project_config_list"], P["project_debug"], P["project_release"]),
    (P["target_config_list"], P["target_debug"], P["target_release"]),
]:
    A(f"\t\t{list_id} = {{")
    A("\t\t\tisa = XCConfigurationList;")
    A("\t\t\tbuildConfigurations = (")
    A(f"\t\t\t\t{dbg},")
    A(f"\t\t\t\t{rel},")
    A("\t\t\t);")
    A("\t\t\tdefaultConfigurationIsVisible = 0;")
    A("\t\t\tdefaultConfigurationName = Release;")
    A("\t\t};")
endsection("XCConfigurationList")

A("\t};")
A('\trootObject = ' + P["project"] + ";")
A("}")

pbxproj_path = os.path.join(ROOT, f"{APP}.xcodeproj", "project.pbxproj")
with open(pbxproj_path, "w", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")
print(f"wrote {pbxproj_path}")

# ---------- xcscheme ----------
scheme = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      runPostActionsOnFailure = "NO">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{P['target']}"
               BuildableName = "{APP}.app"
               BlueprintName = "{APP}"
               ReferencedContainer = "container:{APP}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{P['target']}"
            BuildableName = "{APP}.app"
            BlueprintName = "{APP}"
            ReferencedContainer = "container:{APP}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{P['target']}"
            BuildableName = "{APP}.app"
            BlueprintName = "{APP}"
            ReferencedContainer = "container:{APP}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""
scheme_path = os.path.join(
    ROOT, f"{APP}.xcodeproj", "xcshareddata", "xcschemes", f"{APP}.xcscheme"
)
with open(scheme_path, "w", encoding="utf-8") as f:
    f.write(scheme)
print(f"wrote {scheme_path}")
