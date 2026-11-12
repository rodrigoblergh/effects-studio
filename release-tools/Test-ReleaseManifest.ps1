[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$TestDirectory)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($TestDirectory)
if(Test-Path -LiteralPath $root){throw 'Use a new test directory.'}
[IO.Directory]::CreateDirectory($root)|Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
$rsa=New-Object Security.Cryptography.RSACryptoServiceProvider(3072)
$rsa.PersistKeyInCsp=$false
$key=Join-Path $root 'ephemeral-test-key.xml'
$checks=0
function Assert($condition,$message){if(!$condition){throw $message};$script:checks++}
try {
 [IO.File]::WriteAllText($key,$rsa.ToXmlString($true))
 $stage=Join-Path $root 'stage';[IO.Directory]::CreateDirectory($stage)|Out-Null
 [IO.File]::WriteAllText((Join-Path $stage 'InstallEffectStudio.exe'),'test fixture - not executable')
 $zip=Join-Path $root 'fixture.zip';[IO.Compression.ZipFile]::CreateFromDirectory($stage,$zip)
 $args=@{Package=$zip;PackageUrl='https://example.invalid/releases/fixture.zip';Version='1.7.1';Channel='stable';MinAeMajor=26;MaxAeMajor=27;PrivateKey=$key;Output=(Join-Path $root 'stable.json')}
 & (Join-Path $PSScriptRoot 'New-ReleaseManifest.ps1') @args
 $envelope=Get-Content -LiteralPath $args.Output -Raw|ConvertFrom-Json
 $bytes=[Convert]::FromBase64String($envelope.payload);$signature=[Convert]::FromBase64String($envelope.signature)
 Assert ($rsa.VerifyData($bytes,[Security.Cryptography.CryptoConfig]::MapNameToOID('SHA256'),$signature)) 'Signature did not verify'
 $manifest=[Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json
 Assert ($manifest.channel -ceq 'stable' -and $manifest.version -ceq '1.7.1' -and $manifest.installerRelativePath -ceq 'InstallEffectStudio.exe') 'Wrong manifest contract'
 Assert ($manifest.packageSha256 -ceq (Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant()) 'Wrong package hash'
 Assert ($manifest.packageBytes -eq (Get-Item -LiteralPath $zip).Length) 'Wrong package size'
 Assert (([DateTime]::Parse($manifest.expiresUtc)-[DateTime]::Parse($manifest.issuedUtc)).TotalDays -eq 14) 'Wrong validity'
 $bytes[0]=$bytes[0] -bxor 1
 Assert (!$rsa.VerifyData($bytes,[Security.Cryptography.CryptoConfig]::MapNameToOID('SHA256'),$signature)) 'Tampered payload accepted'
 $args.Channel='beta';$args.Output=Join-Path $root 'beta.json';& (Join-Path $PSScriptRoot 'New-ReleaseManifest.ps1') @args
 $beta=Get-Content -LiteralPath $args.Output -Raw|ConvertFrom-Json
 $betaManifest=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($beta.payload))|ConvertFrom-Json
 Assert ($betaManifest.channel -ceq 'beta') 'Wrong beta channel'
 $publishDir=Join-Path $root 'publisher';[IO.Directory]::CreateDirectory($publishDir)|Out-Null
 $public=Join-Path $publishDir 'public.xml';[IO.File]::WriteAllText($public,$rsa.ToXmlString($false))
 $publishArgs=$args.Clone();$publishArgs.Channel='stable';$publishArgs.Output=Join-Path $publishDir 'stable.json';$publishArgs.PackageUrl='https://github.com/rodrigoblergh/effects-studio/releases/download/v1.7.1/fixture.zip'
 & (Join-Path $PSScriptRoot 'New-ReleaseManifest.ps1') @publishArgs
 & (Join-Path $PSScriptRoot 'Publish-Release.ps1') -Package $zip -Manifest $publishArgs.Output -PublicKey $public -VersionTag 'v1.7.1' -Channel stable -WhatIf
 Assert $true 'Publisher dry run failed'
 $packageStage=Join-Path $root 'package-stage';[IO.Directory]::CreateDirectory($packageStage)|Out-Null
 foreach($name in @('EffectStudioNative.aex','EffectStudioRecorder.exe','EffectStudioUpdater.exe','InstallEffectStudio.exe','Effect Studio.jsx')){[IO.File]::WriteAllText((Join-Path $packageStage $name),'offline fixture')}
 [IO.File]::WriteAllText((Join-Path $packageStage 'VERSION.txt'),'1.7')
 $cfg=@{schema=1;stableManifestUrl='https://example.invalid/stable.json';betaManifestUrl='https://example.invalid/beta.json';pinnedPublicKeyXml=$rsa.ToXmlString($false)}
 [IO.File]::WriteAllText((Join-Path $packageStage 'update-config.json'),($cfg|ConvertTo-Json))
 [IO.File]::WriteAllText((Join-Path $packageStage 'unrelated.txt'),'must not ship')
 $packaged=Join-Path $root 'allowlisted.zip'; & (Join-Path $PSScriptRoot 'Package-Release.ps1') -SourceDirectory $packageStage -OutputZip $packaged
 $archive=[IO.Compression.ZipFile]::OpenRead($packaged);try{Assert ($archive.Entries.Count -eq 8 -and $null -ne $archive.GetEntry('SHA256.json') -and $null -eq $archive.GetEntry('unrelated.txt')) 'Package allowlist failed'}finally{$archive.Dispose()}
 $baseline=$args.Clone();$baseline.Version='1.7';$baseline.Output=Join-Path $root 'baseline.json';$baseline.ValidDays=90
 & (Join-Path $PSScriptRoot 'New-ReleaseManifest.ps1') @baseline
 Assert (Test-Path -LiteralPath $baseline.Output) 'Two-part baseline version refused'
 $cfg.pinnedPublicKeyXml=$rsa.ToXmlString($true);[IO.File]::WriteAllText((Join-Path $packageStage 'update-config.json'),($cfg|ConvertTo-Json))
 $failed=$false;try{& (Join-Path $PSScriptRoot 'Package-Release.ps1') -SourceDirectory $packageStage -OutputZip (Join-Path $root 'private-config.zip')}catch{$failed=$true};Assert $failed 'Private config key packaged'
 $cfg.pinnedPublicKeyXml=$rsa.ToXmlString($false);[IO.File]::WriteAllText((Join-Path $packageStage 'update-config.json'),($cfg|ConvertTo-Json))
 $failed=$false;try{& (Join-Path $PSScriptRoot 'Publish-Release.ps1') -Package $zip -Manifest $publishArgs.Output -PublicKey $public -VersionTag 'v1.7.1' -Channel beta -WhatIf}catch{$failed=$true};Assert $failed 'Publisher wrong channel accepted'
 $failed=$false;try{& (Join-Path $PSScriptRoot 'New-ReleaseManifest.ps1') @args}catch{$failed=$true};Assert $failed 'Existing manifest overwritten'
 $args.Output=Join-Path $root 'unsafe.json';$args.PackageUrl='http://example.invalid/fixture.zip'
 $failed=$false;try{& (Join-Path $PSScriptRoot 'New-ReleaseManifest.ps1') @args}catch{$failed=$true};Assert $failed 'HTTP URL accepted'
 $args.PackageUrl='https://example.invalid/fixture.zip'
 [IO.File]::WriteAllText((Join-Path $stage 'secret.xml'),$rsa.ToXmlString($true))
 $unsafeZip=Join-Path $root 'unsafe.zip';[IO.Compression.ZipFile]::CreateFromDirectory($stage,$unsafeZip);$args.Package=$unsafeZip
 $failed=$false;try{& (Join-Path $PSScriptRoot 'New-ReleaseManifest.ps1') @args}catch{$failed=$true};Assert $failed 'Private key ZIP accepted'
 # Delete only explicit ephemeral secret artifacts created by this test.
 [IO.File]::Delete((Join-Path $stage 'secret.xml'));[IO.File]::Delete($unsafeZip)
 Write-Output ("PASS: $checks release-signing checks; no production key, network or install used.")
} finally {$rsa.Dispose();if([IO.File]::Exists($key)){[IO.File]::Delete($key)};if([IO.File]::Exists((Join-Path $root 'stage/secret.xml'))){[IO.File]::Delete((Join-Path $root 'stage/secret.xml'))};if([IO.File]::Exists((Join-Path $root 'unsafe.zip'))){[IO.File]::Delete((Join-Path $root 'unsafe.zip'))}}
