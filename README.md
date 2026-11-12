# Effect Studio

Effect search, favorites, presets, snapshots, and behind-the-scenes exports for Adobe After Effects on Windows.

## Install

Download the ZIP from [Releases](https://github.com/rodrigoblergh/effects-studio/releases), extract the whole folder, save your project, and close After Effects. Run `InstallEffectStudio.exe` and confirm the After Effects **Support Files** folder. Windows administrator approval is required.

Effect Studio is a native plug-in, not a CEP extension. Open **Window → Effect Studio Search** after installation. Assign the Effect Studio launcher to **Ctrl+Space** in After Effects' Keyboard Shortcuts editor; remove any conflicting FX Console assignment.

The current supported release targets **Windows x64 and After Effects 2026**. See the package's `README.txt` and `VALIDATION.txt` for behavior and tested limits.

## Updates

Version 1.7 adds an Updates button in Settings. Existing users must install the complete updater-enabled package once.

- Startup checks are enabled by default, at most once a day; you can disable them.
- Automatic downloads are optional and off by default.
- Stable and beta channels are separate.
- Signed release metadata and package hashes are verified before installation.
- Installation waits for you to close After Effects and requires Windows approval. It never closes your project automatically.
- Favorites, aliases, shortcuts, and personal preferences are preserved.
- Roll back restores the previous plug-in payload while keeping the update tools available.

Update checking contacts GitHub. It does not upload compositions, projects, presets, or usage data. Windows code-signing reputation is separate from the update signature, so Windows may still show an unknown-publisher prompt.

## Search and capture

Compact search opens at the pointer by default. Expanded browsing includes installed effects and discoverable local animation presets; it stays open over AE and remembers its size. Effects apply to compatible selected layers in one Undo operation.

The camera copies a composition snapshot to the clipboard. Save asks for a destination. Behind-the-scenes export captures the visible composition and its layer controls, with optional Effects and Timeline snapshots. It needs AE's viewer available during capture; it is not a headless renderer.

## Release channels

Version downloads are stored in immutable version releases. The `update-stable` and `update-beta` releases contain signed update metadata, not installers. Download a version ZIP to install manually.
