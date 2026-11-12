# Mac development handoff

Development branches only. Windows stable releases are unchanged. Do not publish these Mac sources as a compatible/stable release until native builds and AE tests pass.

## Align Studio
Repository: https://github.com/rodrigoblergh/align-studio ; branch: macos-support.

    node macos/AlignStudio/tests/launcher-tests.cjs
    node macos/AlignStudio/tests/panel-regressions.cjs
    swift build -c release --package-path macos/UpdateKit
    swift test --package-path macos/UpdateKit

53 panel/path/keyboard regression checks passed on Windows. The 11 authored Swift tests have not yet run. GitHub native jobs were queued at handoff; inspect their latest results before claiming success. The native update helper requires Developer ID/notarization for real installation. Development preview apps are ad-hoc signed and not public installers. Initial installer and signed CEP packaging scripts are under macos/AlignStudio/scripts.

## Effect Studio
Repository: https://github.com/rodrigoblergh/effects-studio ; branch: macos-support.

    cmake -S native/macOS/EffectStudio -B build/mac -DCMAKE_OSX_ARCHITECTURES=arm64
    cmake --build build/mac
    ctest --test-dir build/mac --output-on-failure

This builds the AppKit development preview and platform tests without the Adobe SDK. To build the genuine AE plug-in, add -DAE_SDK_ROOT=/absolute/path/AfterEffectsSDK. SDK headers/resources are licensed separately and are deliberately excluded from GitHub. Xcode command-line tools must provide Rez.

Implemented source: native search and ranking, settings/favorites/aliases/Option shortcuts, persistent category browsing, queued multi-layer SDK application, PNG conversion/clipboard/save support and host SDK render adapter. Native compilation and AE behavior remain unverified. Read PORTING.md for the current feature gaps; preset application, BTS recording/export, complete settings parity and native update-install integration are not ready.

## Live validation after native compilation
Use an isolated AE test project. Verify launch/typing/IME, mixed-layer apply and one Undo, click-away behavior, persistent expanded browser/settings, positioning/resizing, snapshot background/clipboard/save, Align text/null/expression alignment, scrolling and Cmd+Z focus. Preserve existing projects and preferences. Do not remove Gatekeeper/quarantine controls or alter Windows feeds.

Mac update metadata uses distinct platform-specific feeds and platform binding. No Mac feed or stable package has been published.
