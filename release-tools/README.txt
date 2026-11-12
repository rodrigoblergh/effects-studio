Effect Studio signed release workflow

Key generation is an explicit maintainer operation. The owner selected GitHub
rodrigoblergh/effects-studio. Signing/key scripts never upload anything;
Publish-Release.ps1 uploads only when explicitly invoked without -WhatIf.

1. Run New-SigningKey.ps1 once, explicitly, with a NEW private directory outside
   this workspace and all package staging folders. The script restricts its ACL
   to the current Windows account before writing a 4096-bit RSA private XML key.
   Keep an encrypted offline backup. Only the public XML belongs in update-config.json.
2. Build/test the installer and product. A ZIP must contain the fixed root file
   InstallEffectStudio.exe plus its required product payload. Never copy the
   private directory, signing-key.xml, or any private RSA XML into staging.
   Package-Release.ps1 reads VERSION.txt and copies only the seven named product
   files plus optional README.txt/README.md/REVIEW.txt/VALIDATION.txt/RECORDER.txt into a new ZIP. It adds
   SHA256.json for inspection, validates public-only signing config and rejects
   private-key text. This inventory is not a signature; the signed feed authenticates
   the complete ZIP. Never replace an already published version package.
3. Use immutable HTTPS version-package URLs and separate stable/beta endpoints.
   Set pinnedPublicKeyXml and the endpoints in the updater config before shipping.
   Public-key replacement must be delivered through an already trusted release.
4. Run New-ReleaseManifest.ps1 with package path, HTTPS URL, numeric version,
   channel, AE major interval, private-key path and a NEW output filename.
   Default validity is 14 days; maximum is 90 days. Use -ValidDays 90 for a maintained baseline feed. Versions must increase within
   each channel; beta status uses the channel, not a SemVer suffix.
   Renew each stable/beta manifest before expiry, even if its package version has
   not changed: re-sign the same immutable URL/hash/size with fresh timestamps and
   publish only the corresponding feed asset. Expired feeds are rejected by design.
5. Verify the manifest and downloaded package with updater security tests, then
   publish the immutable ZIP first and the signed envelope last. Keep old packages
   available for existing signed manifests until their expiry. Publishing is manual.
   update-config.template.json contains the selected feeds; fill only its PUBLIC key.
   Use Publish-Release.ps1 -WhatIf first. It verifies the signed manifest/package
   locally before any GitHub call. Actual publishing uses existing gh authentication,
   never accepts/logs tokens. Create the distribution version tag first; publishing source is not required.
   The version package upload never uses --clobber. On promotion or retry, an
   existing asset is downloaded into a unique temporary directory and its exact
   length/SHA256 must match the signed manifest before the feed can advance.
   A mismatch stops publication; it never overwrites the immutable package.

Wire contract: JSON envelope {payload,signature}, both Base64. The payload is raw
UTF-8 JSON bytes. Signature is RSA SHA256 PKCS#1 v1.5 over exactly those bytes;
verifiers must not deserialize/re-serialize before verifying. Payload contains
version, channel, minAeMajor, maxAeMajor, packageUrl, packageSha256, packageBytes,
installerRelativePath, issuedUtc and expiresUtc. Fixed installerRelativePath is
InstallEffectStudio.exe. Bounds: envelope256 KiB, payload64 KiB, package200 MiB.

Required acceptance: tampered payload/signature/package rejected; wrong channel,
expired or future-issued manifest rejected; equal/older version rejected; unknown
AE version rejected; unsafe ZIP paths/links/duplicates rejected; no installation
while AE is open. A newer-than-installed release can still be replayed within its
validity unless the updater also stores a trusted per-channel version high-water
mark. Expiry and a current-version comparison alone are not complete rollback defense.

Use ephemeral test keys and isolated directories for tests. Never use the release
private key in automated tests, logs, screenshots, example config or source control.

RSA feed signatures are separate from Windows Authenticode code signing. They
authenticate the package to the updater, but do not make Windows show a verified
publisher or remove SmartScreen/UAC reputation prompts. Those require a separate
Windows code-signing certificate and signing process.


