# Aqua WebKit on Mountain Lion: initial port investigation

## Target and status

Target: OS X **10.8.5 / Darwin 12, Intel x86_64, stock Safari 6**. The exact Safari
6 point release is **6.2.8 (8537.85.17.9.1)**, reported by the target's user;
Safari 6 is not a single frozen private ABI.

Foundation: Wowfunhappy's Mavericks backport of modern Apple WebKit, described in
`CLAUDE.md` as WebKit 625.2.8.11.9. This investigation starts at
`4dd91368bf70214234b35e5e9a59cd231c93f64a`, verified against the remote
`escritosygritos/WebKit-MountainLion` branch `mavericks-backport`. Work belongs on
`mountain-lion-development`; the base branch is unchanged.

**This is source analysis and preparation, not a working port.** The analysis host
is Linux x86_64. No macOS compilation, Safari launch, Mach-O ABI capture, or sandbox
execution has been performed. The original developer's Mavericks VM and its
absolute paths in `CLAUDE.md` are not available here. `install.sh` must not be run
as part of this investigation; system frameworks and Safari remain untouched.

## Existing architecture

`AquaWebKitSupport/README.md` describes a native 10.9 build using vendored clang-22,
a separately supplied MacOSX26.1 SDK, host Command Line Tools headers, Xcode 6.2's
`ibtool`, and CMake/Ninja. Bootstrap builds helper tools, dependencies and polyfills.
The compiler and helper tools themselves need execution compatibility with 10.8;
deployment flags on WebKit do not establish that compatibility.

The support directory owns the CMake overlays, restored legacy API implementations,
polyfill layer, framework staging, sandbox profiles and ABI gates. Preserve this
separation and minimize changes to upstream `Source/`.

The staged layout is Apple's WebKit-601-style layout: public WebKit re-exports
WebKitLegacy; WebCore is nested; private WebKit2 re-exports public WebKit. See
`scripts/framework-layout.sh`. The current ABI gate combines Safari 7, Safari 9,
public SDK and other Mavericks system-client contracts. It is not a Safari 6 gate.

Polyfills distinguish C functions/constants, scoped Objective-C methods, absent
classes and old WTF C++ exports. A method added to a class cannot supply a missing
base class. `polyfill/README.md` also documents private framework symbol lookup;
its assumptions need a separate Darwin-12 audit.

## Compatibility findings

Evidence below names checked-in sources. API introduction dates identify genuine
10.8 gaps; private-image layouts and behavior still require target measurements.

| Area | Source evidence | Required Mountain Lion work |
| --- | --- | --- |
| Deployment target | `cmake/mac10.9-toolchain.cmake` defaults to 10.9; `cmake/OptionsMacAquaWebKit.cmake` adds explicit 10.9 compile and link options. `deps/build_deps.sh` also embeds 10.9 flags and an x86_64-darwin13 libvpx target. | Introduce one validated target selection across compiler configuration, WebKit, polyfills, dependencies and sandbox preprocessing. Keep 10.9 as the default. Rebuild every deployed image for 10.8 and audit load commands; changing one CMake cache entry is insufficient. |
| Host headers and generators | `scripts/host-headers.sh` compiles against host headers; dependency gap objects use `-isysroot /`. The toolchain expects native Darwin builds and finds `mig`. | Supply a compatible macOS build host and 10.8 headers/toolchain inputs, or design an explicit cross-build workflow. Linux headers cannot stand in for Darwin's libc ABI. Audit compiler/helper Mach-O minimum versions first. |
| NSURLSession | `NetworkSessionCocoa.mm` creates session configurations; `polyfill/polyfills/webkit/task_metrics.mm` wraps native session creation. `source/WebKit/UIProcess/LegacyExtensions/LegacyExtensionInfoPlist.mm` uses `NSURLSession.sharedSession`. NSURLSession is introduced in 10.9. | Inventory active session, configuration and task APIs. Adapt the platform backend or provide a behaviorally complete implementation over available facilities. Existing task-metrics and method polyfills do not implement the missing session class hierarchy. |
| Existing curl transport | `cmake/WebKitPlatformAquaWebKit.cmake` adds `NetworkDataTaskCurlCocoa.mm`, WebSocketTaskCurlCocoa and PrivateClickMeasurementCurlLoadTask. The data-task implementation still includes NetworkSessionCocoa. | Reuse the working curl/Cocoa design as the foundation; trace retained Cocoa session, cookie, credential and download dependencies. Selecting curl alone does not remove all NSURLSession use. |
| AppKit appearances | `polyfill/polyfills/methods/AppKit.m` adds methods to NSAppearance and calls `currentAppearance` / `appearanceNamed:`. NSAppearance is introduced in 10.9. | Implement the actually required 10.8 appearance behavior through available AppKit facilities or a correctly scoped missing-class implementation; inventory view/window appearance calls too. Constants for newer appearance names are insufficient. |
| pthread image layout | `polyfill/polyfills/shared/pthread_stack.c` resolves `_pthread_get_stacksize_np` specifically from `/usr/lib/system/libsystem_pthread.dylib`. | Verify Darwin-12 symbol ownership and `pthread_main_thread_np` availability. Audit image-specific resolution independently of symbol presence. Do not guess another image path or silently return fake stack limits. |
| Private framework internals | `polyfill/polyfills/methods/Accelerate.m` resolves vImage's `_SetvImageVectorAvailable` and kernel CPU capabilities and calls them in a constructor. `polyfill/README.md` lists CFNetwork cookie/protection-space and CoreFoundation archive private lookups. | Check every private symbol, signature and object layout against 10.8.5. The Mavericks AVX2 workaround's premise and entry points need target evidence before applying it there. |
| Sandboxing and processes | `sandbox/README.md` documents profiles recovered for Mavericks, its sandbox compiler vocabulary and deployment-target preprocessing. GPU/webpushd profiles are additional adaptations. | Compile all profiles with Darwin 12's real compiler and verify confinement of launched processes, Mach service names, XPC discovery and filesystem access. Preserve confinement; do not bypass failed profiles. |
| Media, graphics, text and security | Dependency build and polyfills cover GStreamer/FFmpeg, VideoToolbox, AudioToolbox, OpenGL/IOSurface, CoreText, Security and CFNetwork. Their current native-symbol audit runs against 10.9. | Repeat strong/weak-import resolution and behavioral tests on 10.8.5. Framework presence alone proves neither symbol availability nor identical semantics. Recheck ICU/system interoperation and the private libc++/system-unwinder boundary. |
| Packaging | `scripts/framework-layout.sh` and the README describe retained stock i386 slices, system framework paths and XPC services. | Validate 10.8 install names, re-export closure, dyld compatibility/current versions and resource expectations in a staging tree. A 64-bit target does not justify copying Mavericks' stock 32-bit slices to Mountain Lion. Installation design is a later, separately reviewed step. |

The list is an initial inventory, not an exhaustive missing-symbol report. Also
audit 10.9-era Foundation facilities such as NSProgress and process-activity APIs
where reached by selected features; do not disable features based solely on names.
Audit build-time SDK availability checks that choose code paths on minimum OS
version, including the support layer's `AdditionalPlatformHave.h` overrides.

## Safari 6 versus Safari 7 integration

Safari 6 already belongs to the WebKit2 era. Targeting the original Safari 6 does
not imply replacing its tab embedding with a WebKit1 WebView, nor using WKWebView,
which arrived later. Safari is a private-API embedder: exported symbols, Objective-C
selectors, callback layouts and process behavior all matter.

The checked-in `docs/MAVERICKS-WEBKIT-ABI-REFERENCE.md` describes Safari 7.0.6 on
10.9.5 (WebKit 9537.78.2): 95 JavaScriptCore, 24 WebKit and 606 WebKit2 imported
symbols. These counts describe that documented baseline, not measured Safari 6
requirements. It documents WKView embedding, versioned WKPage/WKBundle C clients,
an injected bundle in the web process, and legacy WebView utilities. The restored
`source/WebKit/UIProcess/API/mac/WKViewAquaWebKit.mm` explicitly implements Safari
7 SPI and page-client behavior.

For Safari 6, determine rather than assume:

1. Actual framework load paths, dylib ordinals, re-exports, required versions and
   all imports from Safari, Safari.framework, injected bundles and other loaded
   helpers. A symbol exported from the wrong framework is not enough.
2. WKView initializers, Objective-C method signatures, private class/ivar
   assumptions, view geometry, compositing, focus and event delivery.
3. Every versioned client struct Safari registers: field order, size, version,
   callback signatures, ownership and supported old versions. Matching symbol
   names does not establish ABI equivalence.
4. The injected-bundle API and startup handshake, resource paths and process
   launch conventions. Modern WebKit's network-process split must work with the
   older embedder through the compatibility layer.
5. Downloads/resume, authentication, cookie/storage policy, history, Reader,
   extensions, inspector frontend protocol, fullscreen and accessibility behavior.
   Safari 7 working with a classic inspector does not prove Safari 6's frontend works.

The supplied Safari 6 text reports establish the symbol-level observations below.
Safari 6 binaries, disassembly and target SDK headers are not present in this
checkout analysis. A definitive selector and callback-layout comparison remains
outstanding; do not manufacture Safari 6 contracts from Safari 7's text files.
Historical Apple WebKit source corresponding to the target's actual build can
explain old declarations, but the shipped binary remains the ABI authority.

### Observed Safari 6.2.8 framework bindings

User-supplied `Safari6-ABI.zip` and `Safari6-Framework-ABI-2.zip` text captures
report OS X 10.8.5 build 12F2560, Darwin 12.6.0, x86_64. The launcher imports only
`_SafariMain` and `dyld_stub_binder`, and carries
`DYLD_VERSIONED_FRAMEWORK_PATH=/System/Library/StagedFrameworks/Safari`.

Both Safari framework images exist. Their reported identities and unique undefined
symbols attributed by `nm -um` to the three WebKit frameworks are:

| Safari framework location | Current dylib version | JavaScriptCore | WebKit | WebKit2 |
| --- | --- | ---: | ---: | ---: |
| `/System/Library/PrivateFrameworks/Safari.framework/Versions/A/Safari` | 536.30.1 | 87 | 70 | 542 |
| `/System/Library/StagedFrameworks/Safari/Safari.framework/Versions/A/Safari` | 537.85.17 | 95 | 620 | 0 |

The older image's SHA-256 is
`057d7d6dacda9258d7161cb85a43b98a0d7fa1f871c1cfac225ec723dcaff2bd`;
the staged image's is
`6a7c52ccd80ed734ad36518e43f8b907c29d6438ef0d4395a4cafc314feaea1d`.
These identify user-reported images, not independently authenticated Apple artifacts.

The staged image records JavaScriptCore 600.8.7 and WebKit/WebKit2 600.8.9 library
versions. Its 95 JavaScriptCore symbol names exactly match the checked-in Safari 7
contract. Its 620 WebKit imports contain five names outside the union of Safari 7's
WebKit and WebKit2 lists:

- `_WKContextGetOriginDataManager`
- `_WKOriginDataManagerDeleteAllEntries`
- `_WKOriginDataManagerDeleteEntriesForOrigin`
- `_WKOriginDataManagerGetOrigins`
- `_WKPageSetBackgroundExtendsBeyondPage`

All five have implementations in `Source/WebKit/UIProcess/API/C/WKPage.cpp`.
This is source-presence evidence; staged exports, calling conventions, semantics
and old callback layouts require separate checks. Fifteen names in the Safari 7
union are absent from this staged image's import set; retain the Mavericks contract.
Counts describe these two images only, not all Safari helpers or injected bundles.

The launcher requires Safari.framework 537.85.17 and specifies the staged search
path; the staged image matches that requirement while the older copy does not.
This supports using the staged image as the primary 6.2.8 embedder contract.
Loaded-image observation is still required to establish the actual runtime graph.
The updated browser's framework layout is therefore closer to the backport's
601-style re-export design than the original system copy suggests. This does not
resolve Mountain Lion's missing system APIs or prove the port works.

### Observed staged WebKit export surface

The user-supplied `Safari6-WebKit-ABI.zip` captures
`/System/Library/StagedFrameworks/Safari/WebKit.framework/Versions/A/WebKit`.
It reports current version 600.8.9, compatibility version 1.0.0, minimum OS 10.8
and SDK 10.8. Its reported SHA-256 is
`11072f1c4865cf149786799547ea636a857293599df56cb277eaa902c95c8ec0`.

Of the staged Safari framework's 620 unique WebKit imports, 596 appear as direct
defined external symbols in this WebKit export report, including all five names
outside the Safari 7 union listed above. The other 24 names exactly match the
checked-in Safari 7 `safari-needs-from-WebKit.txt` legacy contract. This is a
symbol-name comparison, not a signature, behavioral or backport-binary validation.

The stock image records `LC_REEXPORT_DYLIB` for both:

- `/System/Library/StagedFrameworks/Safari/WebKitLegacy.framework/Versions/A/WebKitLegacy`
- `/System/Library/Frameworks/WebKit.framework/Versions/A/Frameworks/WebCore.framework/Versions/A/WebCore`

The 24 legacy imports therefore require checking the re-export closure rather
than declaring them missing from the product. This also establishes a packaging
difference: the captured stock legacy image is a staged sibling, whereas this
backport nests WebKitLegacy in public WebKit. Compatibility depends on resolving
the old install-name bindings and re-exports, not reproducing every stock pathname.
The static reports do not establish which images actually load at runtime.

Both supplied Safari.framework export reports also contain `_WKBundleInitialize`.
Safari.framework therefore contains an injected-bundle entry point; the absence
of a separately named `.bundle` directory does not establish missing bundle code.
Confirm the path passed to WebKit and the runtime initialization before treating
this as a complete injected-bundle compatibility check.

### Observed WebKitLegacy closure

The supplied `Safari6-Legacy-ABI.zip` captures the staged sibling
`/System/Library/StagedFrameworks/Safari/WebKitLegacy.framework/Versions/A/WebKitLegacy`.
It reports current version 600.8.9, compatibility version 1.0.0 and minimum OS/SDK
10.8, with SHA-256
`ea571c3912e6cfe05b31252cd3c3ad270b3b99cc5312d537e564199ea8841952`.
Its direct defined external symbols include all 24 remaining legacy imports.
Together with the captured WebKit exports and explicit WebKitLegacy re-export,
this accounts for all 620 WebKit-attributed symbol names imported by the captured
staged Safari.framework. It is a static, stock-image symbol-closure check; it does
not validate the backport's exports, Objective-C selectors, callback signatures,
dynamic lookups or runtime loading. The 95 JavaScriptCore imports still require
an export check against the appropriate JavaScriptCore image.

The Safari embedder evidence is sufficient to focus further source work on the
10.8 system API gaps and old client semantics rather than assume an entirely
different Safari 6 embedding architecture. Additional stock-framework captures
should answer a specific unresolved question, not serve as a substitute for
implementing and testing the port.

### Read-only evidence collection

`AquaWebKitSupport/host-abi/capture-host-abi.sh` collects x86_64 library references,
load commands, eager/lazy/weak bindings, undefined symbols, exports, Objective-C
metadata and SHA-256 identifiers. It writes only to a new output directory, checks
every supplied input has an x86_64 slice, and marks successful completion explicitly.
It never launches Safari or writes to the input images. An incomplete capture has
no `COMPLETE` file. The script is preparatory tooling, not a runtime compatibility
fix or an ABI pass/fail gate.

On a stock 10.8.5 machine with Command Line Tools, first record Safari's bundle
version and identify its actual executables, framework images and injected bundles.
For example, the main executable can be captured with:

```sh
bash AquaWebKitSupport/host-abi/capture-host-abi.sh \
    /tmp/safari6-main-abi /Applications/Safari.app/Contents/MacOS/Safari
```

Supply the remaining images explicitly in a separate capture or in the same
invocation. The script does not discover the complete dependency graph or dynamic
`dlsym`/selector use. `otool -ov` provides metadata, not a complete message-send
trace. Review dynamic calls and struct layouts through historical source and
disassembly. Record the Safari Info.plist version alongside the capture. Inspect
reports before sharing: paths and Objective-C metadata may identify local software.
Do not commit Apple binaries or generated capture files.

## Implementation sequence and acceptance criteria

1. **Freeze evidence:** capture exact Safari 6/10.8.5 artifacts and compare binding
   ownership and old client definitions with the Mavericks contracts. Add separately
   identified Mountain Lion contracts and retain all Mavericks gates.
2. **Prove toolchain viability:** inspect and execute compiler/helper tools on the
   supported macOS builder; validate modern SDK plus 10.8 libc headers and resource
   tools. Use isolated output/cache directories for 10.8 and 10.9. Reusing 10.9
   dependency archives would conceal minimum-version and native-symbol problems.
3. **Select the target coherently:** centralize deployment/triple configuration
   across toolchain, dependencies, polyfills, WebKit and profile preprocessing,
   retaining 10.9 defaults. Audit Mach-O minimum versions, linked libraries,
   re-exports, unresolved strong imports and potentially absent weak calls.
4. **Close proven runtime gaps:** implement complete required session/appearance
   behavior, fix verified private lookups and restore only Safari-6-required ABI.
   Prefer existing native symbols, build configuration and scoped polyfills before
   upstream source changes. Each change needs a focused behavioral test on 10.8
   and a Mavericks regression check.
5. **Validate in stages:** link/load staged frameworks in a disposable macOS test
   environment; prove JSC execution, WK1 and WK2 test-driver behavior, process
   startup and sandbox enforcement. Then test unmodified Safari 6 embedding,
   navigation, scripting, HTTPS, cookies, authentication, redirects, downloads,
   extensions, media, inspector and accessibility. Include heavy real sites and
   inspect crash logs. Retest Safari 7 on 10.9.5 with the default build.

Deployment flags retain their Mavericks defaults. No guessed Objective-C class
stubs, no-op APIs, broad availability bypasses or sandbox exemptions are part of
this change.

### First networking refactor: transport session policy

`CocoaCurlSessionPolicy.h` defines the three session-selected values used by the
HTTP and WebSocket curl transports: minimum TLS protocol, preferred-client-identity
lookup, and a retained proxy dictionary. `SessionWrapper::curlSessionPolicy()`
reads them from its native session configuration for each transport exchange.
The callers retain their existing credential/privacy partition selection and
consume these values through this interface. The proxy dictionary remains owned
while the policy and transport options hold it; TLS and client-certificate values
come from the same native configuration as before.

This separates transport callers from NSURLSession configuration access, but the
policy producer, session initialization, credential storage and native task paths
still depend on NSURLSession. It does not enable networking on 10.8. The next
implementation step must supply partition policy independently of native session
creation and trace every native-task caller before selecting an alternate backend.
The session abstraction must preserve private/stateless isolation, credential
deletion, proxy updates and client certificate decisions; empty session classes
cannot satisfy that requirement.

Validation here is source-level: the PR-base divergence gate and whitespace checks
pass. The policy interface uses Apple CoreFoundation/Security types and WTF's
RetainPtr; it does not declare NSURLSession types. Objective-C++ compilation and
runtime checks remain unrun on Linux. Before treating the refactor as verified,
build the affected NetworkSessionCocoa, NetworkDataTaskCurlCocoa and WebSocketTask
translation units on macOS, then compare HTTP/WebSocket proxy routing, TLS floors,
client certificate handling, redirects and credential/privacy partitions on
Mavericks. Repeat those checks against the future 10.8 policy producer.

## Validation boundary

Available here: source inspection, shell syntax/CLI checks, Git diff/whitespace
validation and verification of the base-branch commit. The collector's real
Mach-O commands require macOS and are **unrun** here. Its help, invalid-argument
and non-Darwin rejection paths can be checked on Linux.

Required before a working-port claim: macOS toolchain execution, full 10.8-targeted
build, strong/weak symbol and export audits against the exact target, sandbox
compilation/application, Safari 6 runtime tests and Mavericks regression tests.
The repository-wide divergence gate additionally needs its upstream Git baseline;
a check against this PR's base only demonstrates that this change adds no upstream
source divergence.
