[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SourceDirectory,
 [Parameter(Mandatory=$true)][string]$OutputZip)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$source=[IO.Path]::GetFullPath($SourceDirectory)
$output=[IO.Path]::GetFullPath($OutputZip)
if(Test-Path -LiteralPath $output){throw 'Output already exists; immutable packages are never overwritten.'}
$required=@('EffectStudioNative.aex','EffectStudioRecorder.exe','EffectStudioUpdater.exe','InstallEffectStudio.exe','update-config.json','Effect Studio.jsx','VERSION.txt')
$optional=@('README.txt','README.md','REVIEW.txt','VALIDATION.txt','RECORDER.txt')
$names=@($required)+@($optional|Where-Object{Test-Path -LiteralPath (Join-Path $source $_)})
$version=([IO.File]::ReadAllText((Join-Path $source 'VERSION.txt'))).Trim()
if($version -notmatch '^\d+\.\d+(\.\d+){0,2}$'){throw 'VERSION.txt must contain one numeric release version.'}
[Version]::Parse($version)|Out-Null
$config=Get-Content -LiteralPath (Join-Path $source 'update-config.json') -Raw|ConvertFrom-Json
if($config.schema -ne 1){throw 'Invalid updater config schema.'}
foreach($endpoint in @($config.stableManifestUrl,$config.betaManifestUrl)){$uri=[Uri]$endpoint;if(!$uri.IsAbsoluteUri -or $uri.Scheme -cne 'https' -or $uri.UserInfo -or $uri.Fragment){throw 'Both update feeds must be configured HTTPS URLs.'}}
$key=New-Object Security.Cryptography.RSACryptoServiceProvider;$key.PersistKeyInCsp=$false
try{$key.FromXmlString($config.pinnedPublicKeyXml);if(!$key.PublicOnly -or $key.KeySize -lt 3072){throw 'Package config must pin a public-only RSA key of at least3072 bits.'}}finally{$key.Dispose()}
$items=@();$total=0L
foreach($name in $names){
 $path=Join-Path $source $name;$file=Get-Item -LiteralPath $path
 if($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Not a plain package file: $name"}
 $total+=$file.Length;if($total -gt 209715200){throw 'Uncompressed release files exceed200 MiB.'}
 $bytes=[IO.File]::ReadAllBytes($path)
 if($name -match '\.(txt|md|json|jsx)$'){$text=[Text.Encoding]::UTF8.GetString($bytes);if($text -match '(?is)<RSAKeyValue>.*<(D|P|Q)>|BEGIN (RSA |ENCRYPTED )?PRIVATE KEY'){throw 'Private key content detected in an allowlisted file.'}}
 $sha=[Security.Cryptography.SHA256]::Create();try{$hash=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
 $items+=@{name=$name;bytes=$bytes;hash=$hash}
}
$hashes=[ordered]@{};foreach($item in $items){$hashes[$item.name]=$item.hash}
$inventory=[ordered]@{version=$version;files=$hashes}|ConvertTo-Json -Depth 4
$stream=$null;$archive=$null;$created=$false
try{
 $stream=New-Object IO.FileStream($output,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$created=$true
 $archive=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
 foreach($item in $items){$entry=$archive.CreateEntry($item.name,[IO.Compression.CompressionLevel]::Optimal);$entryStream=$entry.Open();try{$entryStream.Write($item.bytes,0,$item.bytes.Length)}finally{$entryStream.Dispose()}}
 $entry=$archive.CreateEntry('SHA256.json');$entryStream=$entry.Open();try{$bytes=[Text.Encoding]::UTF8.GetBytes($inventory);$entryStream.Write($bytes,0,$bytes.Length)}finally{$entryStream.Dispose()}
 $archive.Dispose();$archive=$null;$stream.Dispose();$stream=$null
 if((Get-Item -LiteralPath $output).Length -gt 209715200){throw 'Compressed package exceeds updater limit.'}
}catch{if($archive){$archive.Dispose();$archive=$null};if($stream){$stream.Dispose();$stream=$null};if($created){[IO.File]::Delete($output)};throw}finally{if($archive){$archive.Dispose()};if($stream){$stream.Dispose()}}
Write-Output ("Packaged Effect Studio $version with $($items.Count) allowlisted files and SHA256.json. No upload performed.")
