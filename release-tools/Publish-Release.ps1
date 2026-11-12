[CmdletBinding(SupportsShouldProcess=$true)]
param([Parameter(Mandatory=$true)][string]$Package,
 [Parameter(Mandatory=$true)][string]$Manifest,
 [Parameter(Mandatory=$true)][string]$PublicKey,
 [Parameter(Mandatory=$true)][string]$VersionTag,
 [ValidateSet('stable','beta')][string]$Channel='stable')
$ErrorActionPreference='Stop'
$repo='rodrigoblergh/effects-studio'
function Invoke-GhCLI([string[]]$Arguments){& gh.exe @Arguments;if($LASTEXITCODE -ne 0){throw 'GitHub operation failed. Feed was not advanced unless its final upload already succeeded.'}}
$envelope=Get-Content -LiteralPath $Manifest -Raw|ConvertFrom-Json
$payload=[Convert]::FromBase64String($envelope.payload)
$signature=[Convert]::FromBase64String($envelope.signature)
$rsa=New-Object Security.Cryptography.RSACryptoServiceProvider;$rsa.PersistKeyInCsp=$false
try{$rsa.FromXmlString([IO.File]::ReadAllText([IO.Path]::GetFullPath($PublicKey)));if(!$rsa.VerifyData($payload,[Security.Cryptography.CryptoConfig]::MapNameToOID('SHA256'),$signature)){throw 'Manifest signature is invalid.'}}finally{$rsa.Dispose()}
$data=[Text.Encoding]::UTF8.GetString($payload)|ConvertFrom-Json
if($data.releaseLine -cne 'v1'){throw 'Only signed public releaseLine v1 manifests may use these feeds.'}
if($data.channel -cne $Channel){throw 'Manifest channel differs.'}
if($VersionTag -notmatch '^v\d+(\.\d+){0,3}$'){throw 'Invalid version tag.'}
function Normalize-ReleaseVersion([string]$Value){
 if($Value -notmatch '^\d+(\.\d+){0,3}$'){throw 'Invalid numeric version.'}
 $parts=@($Value.Split('.'));while($parts.Count -lt 4){$parts+='0'}
 return [Version]::Parse(($parts -join '.'))
}
if((Normalize-ReleaseVersion $VersionTag.Substring(1)) -ne (Normalize-ReleaseVersion $data.version)){throw 'Tag version differs from signed release.'}
$file=Get-Item -LiteralPath $Package
if($file.Name -notmatch '^[A-Za-z0-9._ -]+\.zip$'){throw 'Use a plain ZIP asset name without glob characters.'}
if($VersionTag -ceq 'v1' -and ($data.version -cne '1.0' -or $file.Name -cne 'Effect-Studio-v1.zip')){throw 'The first public release uses tag v1, version 1.0 and Effect-Studio-v1.zip.'}
$expected='https://github.com/'+$repo+'/releases/download/'+$VersionTag+'/'+[Uri]::EscapeDataString($file.Name)
if($data.packageUrl -cne $expected){throw 'Signed URL does not match this immutable GitHub release/package.'}
if($data.packageBytes -ne $file.Length -or $data.packageSha256 -cne (Get-FileHash -LiteralPath $Package -Algorithm SHA256).Hash.ToLowerInvariant()){throw 'Package differs from signed metadata.'}
if([DateTimeOffset]::Parse($data.expiresUtc) -le [DateTimeOffset]::UtcNow){throw 'Manifest expired.'}
if([IO.Path]::GetFileName($Manifest) -cne ($Channel+'.json')){throw 'Manifest filename must be stable.json or beta.json for its channel.'}
if(!$PSCmdlet.ShouldProcess($repo,"Publish immutable $VersionTag package, then advance $Channel signed feed")){return}
Invoke-GhCLI -Arguments @('auth','status','--hostname','github.com')
# Maintainer must create the distribution tag first. No force tags or package overwrite.
Invoke-GhCLI -Arguments @('api',"repos/$repo/git/ref/tags/$VersionTag",'--silent')
& gh.exe release view $VersionTag --repo $repo *> $null
if($LASTEXITCODE -ne 0){$create=@('release','create',$VersionTag,'--repo',$repo,'--verify-tag','--title',"Effect Studio $($data.version)",'--notes','Signed Effect Studio release.');if($Channel -eq 'beta'){$create+='--prerelease'};Invoke-GhCLI -Arguments $create}
$releaseJson=& gh.exe release view $VersionTag --repo $repo --json assets
if($LASTEXITCODE -ne 0){throw 'Could not inspect existing release assets.'}
$assets=@(($releaseJson|ConvertFrom-Json).assets|Where-Object{$_.name -ceq $file.Name})
if($assets.Count -gt 1){throw 'Ambiguous existing package assets.'}
if($assets.Count -eq 1){
 $tempDir=Join-Path ([IO.Path]::GetTempPath()) ('EffectStudioPublish-'+[Guid]::NewGuid().ToString('N'))
 [IO.Directory]::CreateDirectory($tempDir)|Out-Null
 try{
  Invoke-GhCLI -Arguments @('release','download',$VersionTag,'--repo',$repo,'--pattern',$file.Name,'--dir',$tempDir)
  $download=Join-Path $tempDir $file.Name
  if(!(Test-Path -LiteralPath $download) -or (Get-Item -LiteralPath $download).Length -ne $data.packageBytes -or (Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLowerInvariant() -cne $data.packageSha256){throw 'Existing immutable package differs; it will not be overwritten.'}
 }finally{if(Test-Path -LiteralPath (Join-Path $tempDir $file.Name)){[IO.File]::Delete((Join-Path $tempDir $file.Name))};if([IO.Directory]::Exists($tempDir)){[IO.Directory]::Delete($tempDir,$false)}}
}else{Invoke-GhCLI -Arguments @('release','upload',$VersionTag,$file.FullName,'--repo',$repo)}
$feedTag='update-v1-'+$Channel
& gh.exe release view $feedTag --repo $repo *> $null
if($LASTEXITCODE -ne 0){Invoke-GhCLI -Arguments @('release','create',$feedTag,'--repo',$repo,'--title',"Effect Studio $Channel update feed",'--notes','Signed update metadata. Packages are stored in immutable version releases.','--prerelease')}
# Mutable feed is updated LAST. This does not overwrite a version package.
Invoke-GhCLI -Arguments @('release','upload',$feedTag,([IO.Path]::GetFullPath($Manifest)),'--repo',$repo,'--clobber')
Write-Output "Published $Channel metadata after immutable package upload."


