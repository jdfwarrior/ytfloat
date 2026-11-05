#!/usr/bin/env python3
"""Regenerate the dependency-free Xcode project from the same sources as SwiftPM."""
from pathlib import Path
import hashlib, json
root = Path(__file__).resolve().parent.parent
objects = {}
def ident(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def obj(identity, isa, **fields):
    key = ident(identity); objects[key] = dict(isa=isa, **fields); return key
refs = {}
for path in sorted((root/'Sources').rglob('*.swift')):
    rel = str(path.relative_to(root))
    refs[rel] = obj('file:'+rel, 'PBXFileReference', lastKnownFileType='sourcecode.swift', path=rel, sourceTree='<group>')
resources = obj('resources', 'PBXFileReference', lastKnownFileType='folder', path='Sources/YTFloat/Resources', sourceTree='<group>')
icon = obj('icon', 'PBXFileReference', lastKnownFileType='image.icns', path='Config/YTFloat.icns', sourceTree='<group>')
plist = obj('plist', 'PBXFileReference', lastKnownFileType='text.plist.xml', path='Config/Info.plist', sourceTree='<group>')
app_product = obj('app-product', 'PBXFileReference', explicitFileType='wrapper.application', path='YTFloat.app', sourceTree='BUILT_PRODUCTS_DIR')
cli_product = obj('cli-product', 'PBXFileReference', explicitFileType='compiled.mach-o.executable', path='ytfloat', sourceTree='BUILT_PRODUCTS_DIR')
products = obj('products', 'PBXGroup', children=[app_product, cli_product], name='Products', sourceTree='<group>')
main = obj('main-group', 'PBXGroup', children=list(refs.values())+[resources, icon, plist, products], sourceTree='<group>')

def source_phase(prefix, paths):
    files = [obj(prefix+':'+p, 'PBXBuildFile', fileRef=refs[p]) for p in paths]
    return obj(prefix+'-sources', 'PBXSourcesBuildPhase', buildActionMask=2147483647, files=files, runOnlyForDeploymentPostprocessing=0)
shared = [p for p in refs if p.startswith('Sources/YTFloatCore/')]
app_sources = source_phase('app', shared+[p for p in refs if p.startswith('Sources/YTFloat/')])
cli_sources = source_phase('cli', shared+[p for p in refs if p.startswith('Sources/CLI/')])
resource_file = obj('resources-build', 'PBXBuildFile', fileRef=resources)
icon_file = obj('icon-build', 'PBXBuildFile', fileRef=icon)
resource_phase = obj('resource-phase', 'PBXResourcesBuildPhase', buildActionMask=2147483647, files=[resource_file, icon_file], runOnlyForDeploymentPostprocessing=0)
copy_file = obj('cli-copy-build', 'PBXBuildFile', fileRef=cli_product, settings={'ATTRIBUTES':['CodeSignOnCopy']})
copy_phase = obj('copy-cli', 'PBXCopyFilesBuildPhase', buildActionMask=2147483647, dstPath='Contents/Helpers', dstSubfolderSpec=1, files=[copy_file], name='Embed CLI', runOnlyForDeploymentPostprocessing=0)

def configs(prefix, extra):
    entries = []
    for mode in ['Debug', 'Release']:
        settings = {'SDKROOT':'macosx', 'MACOSX_DEPLOYMENT_TARGET':'14.0', 'SWIFT_VERSION':'5.0',
                    'CLANG_ENABLE_MODULES':'YES', 'CODE_SIGN_IDENTITY':'-', 'CODE_SIGN_STYLE':'Manual',
                    'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-Osize',
                    'SWIFT_COMPILATION_MODE':'singlefile' if mode=='Debug' else 'wholemodule',
                    'DEBUG_INFORMATION_FORMAT':'dwarf' if mode=='Debug' else 'dwarf-with-dsym',
                    'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if mode=='Debug' else '',
                    'ENABLE_HARDENED_RUNTIME':'YES',
                    'SWIFT_ACTIVE_COMPILATION_CONDITIONS[sdk=macosx27*]':'$(inherited) YTFLOAT_SDK_27', **extra}
        entries.append(obj(prefix+mode, 'XCBuildConfiguration', buildSettings=settings, name=mode))
    return obj(prefix+'config-list', 'XCConfigurationList', buildConfigurations=entries, defaultConfigurationIsVisible=0, defaultConfigurationName='Release')
cli_target = obj('cli-target', 'PBXNativeTarget', buildConfigurationList=configs('cli', {'PRODUCT_NAME':'ytfloat','PRODUCT_MODULE_NAME':'YTFloatCLI','SKIP_INSTALL':'YES'}), buildPhases=[cli_sources], buildRules=[], dependencies=[], name='YTFloatCLI', productName='ytfloat', productReference=cli_product, productType='com.apple.product-type.tool')
proxy = obj('cli-proxy', 'PBXContainerItemProxy', containerPortal=ident('project'), proxyType=1, remoteGlobalIDString=cli_target, remoteInfo='YTFloatCLI')
dependency = obj('cli-dependency', 'PBXTargetDependency', target=cli_target, targetProxy=proxy)
app_target = obj('app-target', 'PBXNativeTarget', buildConfigurationList=configs('app', {'PRODUCT_NAME':'YTFloat','PRODUCT_BUNDLE_IDENTIFIER':'app.ytfloat.YTFloat','INFOPLIST_FILE':'Config/Info.plist','GENERATE_INFOPLIST_FILE':'NO','COMBINE_HIDPI_IMAGES':'YES'}), buildPhases=[app_sources, resource_phase, copy_phase], buildRules=[], dependencies=[dependency], name='YTFloat', productName='YTFloat', productReference=app_product, productType='com.apple.product-type.application')
project = obj('project', 'PBXProject', attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'2600'}, buildConfigurationList=configs('project', {}), compatibilityVersion='Xcode 14.0', developmentRegion='en', hasScannedForEncodings=0, knownRegions=['en','Base'], mainGroup=main, productRefGroup=products, projectDirPath='', projectRoot='', targets=[app_target, cli_target])
def encode(v, level=0):
    pad='\t'*level
    if isinstance(v,dict): return '{\n'+''.join(pad+'\t'+json.dumps(k)+' = '+encode(value,level+1)+';\n' for k,value in v.items())+pad+'}'
    if isinstance(v,list): return '(\n'+''.join(pad+'\t'+encode(x,level+1)+',\n' for x in v)+pad+')'
    if isinstance(v,int): return str(v)
    return json.dumps(v)
p=root/'YTFloat.xcodeproj'; p.mkdir(exist_ok=True)
(p/'project.pbxproj').write_text('// !$*UTF8*$!\n'+encode(dict(archiveVersion=1,classes={},objectVersion=56,objects=objects,rootObject=project))+'\n')
s=p/'xcshareddata/xcschemes'; s.mkdir(parents=True,exist_ok=True)
(s/'YTFloat.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="YTFloat.app" BlueprintName="YTFloat" ReferencedContainer="container:YTFloat.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="YTFloat.app" BlueprintName="YTFloat" ReferencedContainer="container:YTFloat.xcodeproj"/></BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{app_target}" BuildableName="YTFloat.app" BlueprintName="YTFloat" ReferencedContainer="container:YTFloat.xcodeproj"/></BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated YTFloat.xcodeproj')
