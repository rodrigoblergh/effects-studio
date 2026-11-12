[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Package,
 [Parameter(Mandatory=$true)][string]$PackageUrl,
 [Parameter(Mandatory=$true)][string]$Version,
 [Parameter(Mandatory=$true)][ValidateSet('stable','beta')][string]$Channel,
 [Parameter(Mandatory=$true)][int]$MinAeMajor,
 [Parameter(Mandatory=$true)][int]$MaxAeMajor,
 [Parameter(Mandatory=$true)][string]$PrivateKey,
 [Parameter(Mandatory=$true)][string]$Output,
 [ValidateRange(1,90)][int]$ValidDays=14)
$ErrorActionPreference='Stop'
if($Version -notmatch '^\d+\.\d+(\.\d+){0,2}$'){throw 'Use a numeric two- to four-part version; channel carries beta status.'}
$parsed=[Version]::Parse($Version)
if($MinAeMajor -lt 1 -or $MaxAeMajor -lt $MinAeMajor -or $MaxAeMajor -gt 999){throw 'Invalid AE compatibility interval.'}
$uri=[Uri]$PackageUrl
if(!$uri.IsAbsoluteUri -or $uri.Scheme -cne 'https' -or $uri.UserInfo -or $uri.Fragment){throw 'Package URL must be absolute HTTPS without credentials or fragment.'}
$packagePath=[IO.Path]::GetFullPath($Package)
$keyPath=[IO.Path]::GetFullPath($PrivateKey)
$outPath=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $outPath){throw 'Manifest output already exists; choose a new path.'}
$file=Get-Item -LiteralPath $packagePath
if($file.PSIsContainer -or $file.Length -lt 1 -or $file.Length -gt 209715200){throw 'Package must contain 1..200 MiB.'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::OpenRead($packagePath)
try {
 $installerCount=0
 foreach($entry in $archive.Entries){
  if($entry.FullName -ceq 'InstallEffectStudio.exe'){$installerCount++}
  if($entry.FullName -match '(?i)(signing-key|private[-_]?key|\.pfx$|\.p12$|\.pem$|\.key$)'){throw 'Package contains possible private key material.'}
  if($entry.FullName -match '(?i)\.(xml|json|txt)$'){
   if($entry.Length -gt 16777216){throw 'Text package entry exceeds inspection limit.'}
   $reader=New-Object IO.StreamReader($entry.Open())
   try{$content=$reader.ReadToEnd();if($content -match '(?is)<RSAKeyValue>.*<(D|P|Q)>|BEGIN (RSA |ENCRYPTED )?PRIVATE KEY'){throw 'Package contains private key material.'}}finally{$reader.Dispose()}
  }
 }
 if($installerCount -ne 1){throw 'Package must contain exactly one root InstallEffectStudio.exe.'}
} finally {$archive.Dispose()}
# Signing consumes exactly one private key file, never discovers or packages keys.
$privateXml=[IO.File]::ReadAllText($keyPath)
$rsa=New-Object Security.Cryptography.RSACryptoServiceProvider
$rsa.PersistKeyInCsp=$false
try {
 $rsa.FromXmlString($privateXml)
 if($rsa.KeySize -lt 3072 -or $rsa.PublicOnly){throw 'A private RSA key of at least 3072 bits is required.'}
 $now=[DateTime]::UtcNow
 $payload=[ordered]@{version=$Version;channel=$Channel;minAeMajor=$MinAeMajor;maxAeMajor=$MaxAeMajor;packageUrl=$uri.AbsoluteUri;packageSha256=(Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant();packageBytes=[long]$file.Length;installerRelativePath='InstallEffectStudio.exe';issuedUtc=$now.ToString('o');expiresUtc=$now.AddDays($ValidDays).ToString('o')}
 $bytes=[Text.Encoding]::UTF8.GetBytes(($payload|ConvertTo-Json -Compress))
 if($bytes.Length -gt 65536){throw 'Manifest payload too large.'}
 $signature=$rsa.SignData($bytes,[Security.Cryptography.CryptoConfig]::MapNameToOID('SHA256'))
 $envelope=[ordered]@{payload=[Convert]::ToBase64String($bytes);signature=[Convert]::ToBase64String($signature)}
 $text=$envelope|ConvertTo-Json -Compress
 [IO.File]::WriteAllText($outPath,$text,(New-Object Text.UTF8Encoding($false)))
} finally {$rsa.Dispose();$privateXml=$null}
Write-Output ('Signed '+$Channel+' '+$Version+' manifest. No upload was performed.')


