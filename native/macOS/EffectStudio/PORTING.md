# Effect Studio macOS port — development only

AppKit modeless search implementation, shared original typo/accent ranking, native IME input, pointer placement constrained to its screen, keyboard/mouse acceptance and one queued stable effect ID with a host snapshot generation. Foundation normalizes Unicode before the portable search core. UI delegates never invoke AE APIs. The host must compare comp/layer IDs and generation in its idle callback, then apply every compatible selected layer in one balanced undo group; mismatched selection must reject the request.

Build on the user's Mac with Xcode command-line tools:

    cmake -S native/macOS/EffectStudio -B build/mac-effect -DCMAKE_OSX_ARCHITECTURES=arm64
    cmake --build build/mac-effect

Default architectures are arm64 and x86_64. The explicit preview app is a UI development harness, not an AE plugin; it does not apply effects. No Mac compile or AE test has been performed on the Windows development machine. Closing/hiding preview search leaves the harness running; quit it with Cmd+Q.

## Windows dependency audit and remaining parity work

* Host: HWND/foreground ownership, command menu lookup and process launch must become NSWindow/NSApplication and SDK-native host callbacks. Adobe AEGP effect/collection/undo APIs can be reused, but Mac SDK entrypoint, PiPL resource and bundle metadata must be built and validated, not inferred from a renamed .aex.
* UI: initial expanded persistent/resizable category browser, favorites/alias/Option1–9 editor, persistent centered draggable Settings and explicit center action are implemented. Compact empty queries show favorites only. Browser stays open after acceptance and AE idle refreshes selection snapshots. App-local Escape ignores IME, modal windows and sheets. Actual AppKit compilation and interaction checks are pending. Full Windows layout, theme/placement choices, favorites manager polish and remaining utility actions are not yet equivalent.
* Preferences/presets: favorites, aliases, shortcuts and startup view now use atomic JSON at ~/Library/Application Support/Effect Studio/preferences.json; window frames use scoped NSWindow autosave keys. Presets.mm now implements external app/Document roots, nested .ffx discovery, no-UI Finder alias resolution, inode cycle guards and Unicode-safe stable paths. PresetTests covers fixture traversal, symlink cycle, stable IDs, removed files and safe ExtendScript generation. These sources are not yet compiled on Mac. Catalog integration and SDK preset application are NOT WIRED in this checkpoint; override application and full preference migration also remain unfinished.
* Capture: retain SDK composition render, replace GDI+/clipboard with CGImage/ImageIO and NSPasteboard; preserve cached Save Capture and opaque comp-background behavior.
* BTS: Windows Graphics Capture, Media Foundation, input hooks, HWND crop metadata and Windows helper protocols require ScreenCaptureKit/AVFoundation equivalents, explicit recording permission, verified native controls/frame freshness, cancellation and restoration. No synthetic control-box substitute.
* Updater/installer: Windows EXE/UAC bootstrap is incompatible. Build an independently signed Mac helper, same signed product/channel/version checks, per-user install transaction and rollback, appropriate Developer ID/notarization and universal payload.
* Lifecycle: host idle callback must drop pending work on app switch, selected-layer changes or shutdown. No global keyboard hook or key injection. AE controls its launcher shortcut.

## Private SDK host build

An initial real AEGP adapter is now present in NativeHost.mm. It enumerates actual installed effects, snapshots selected layer IDs (including property selections), revalidates selection and foreground on queued acceptance, and applies to compatible mixed layer types from the registered idle callback in one SDK Undo group. Reentrant shutdown retains state until callback unwind. None of this has yet been compiled or exercised on Mac AE.

    cmake -S native/macOS/EffectStudio -B build/mac-effect-sdk -DAE_SDK_ROOT=/private/path/AfterEffectsSDK -DCMAKE_OSX_ARCHITECTURES=arm64
    cmake --build build/mac-effect-sdk

The optional target creates a genuine MODULE .plugin bundle and compiles the project's own PiPL resource using Apple's Rez and Adobe's external resource definitions. Dependencies are the locally licensed SDK Examples/Headers (including SP) and Examples/Resources. No SDK files belong in this repository or public CI. The user's Xcode installation must provide Rez. The preview UI build needs no Adobe SDK.

The resulting SDK bundle is an unsigned development artifact. Signature/notarization, actual AE loading, IME/focus, effect selection and single-Undo tests remain required before distribution. This initial source is not feature parity or a release candidate.
