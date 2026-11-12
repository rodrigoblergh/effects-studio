[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$TestDirectory)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($TestDirectory)
if(Test-Path -LiteralPath $root){throw 'Choose a new test directory.'}
[IO.Directory]::CreateDirectory($root)|Out-Null
$source=@'
using System;using System.IO;using System.Web.Script.Serialization;
class FakeGh{
 static int Main(string[] a){
  string log=Environment.GetEnvironmentVariable("ES_FAKE_GH_LOG");if(String.IsNullOrEmpty(log))return 99;
  File.AppendAllText(log,new JavaScriptSerializer().Serialize(a)+"\n");
  if(a.Length>=3&&a[0]=="release"&&a[1]=="view"&&Array.IndexOf(a,"--json")>=0){Console.WriteLine(Environment.GetEnvironmentVariable("ES_FAKE_GH_EXISTING")=="1"?"{\"assets\":[{\"name\":\"Effect-Studio-v1.zip\"}]}":"{\"assets\":[]}");}
  if(a.Length>=3&&a[0]=="release"&&a[1]=="download"){
   int index=Array.IndexOf(a,"--dir");if(index<0||index+1>=a.Length)return 98;
   string dest=Path.Combine(a[index+1],"Effect-Studio-v1.zip");File.Copy(Environment.GetEnvironmentVariable("ES_FAKE_GH_PACKAGE"),dest);
   if(Environment.GetEnvironmentVariable("ES_FAKE_GH_TAMPER")=="1")File.AppendAllText(dest,"tampered");
  }return 0;
 }
}
'@
[IO.File]::WriteAllText((Join-Path $root 'FakeGh.cs'),$source)
$csc=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
& $csc /nologo /target:exe /reference:System.Web.Extensions.dll ("/out:"+(Join-Path $root 'gh.exe')) (Join-Path $root 'FakeGh.cs')
if($LASTEXITCODE -ne 0){throw 'Fake executable compilation failed.'}
$oldPath=$env:PATH;$env:PATH=$root+';'+$env:PATH
$rsa=New-Object Security.Cryptography.RSACryptoServiceProvider(3072);$rsa.PersistKeyInCsp=$false
$key=Join-Path $root 'ephemeral.xml';$public=Join-Path $root 'public.xml';$zip=Join-Path $root 'Effect-Studio-v1.zip';$manifest=Join-Path $root 'stable.json';$log=Join-Path $root 'calls.jsonl'
try{
 [IO.File]::WriteAllText($key,$rsa.ToXmlString($true));[IO.File]::WriteAllText($public,$rsa.ToXmlString($false))
 $stage=Join-Path $root 'stage';[IO.Directory]::CreateDirectory($stage)|Out-Null
 [IO.File]::WriteAllText((Join-Path $stage 'InstallEffectStudio.exe'),'offline placeholder')
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 [IO.Compression.ZipFile]::CreateFromDirectory($stage,$zip)
 & (Join-Path $PSScriptRoot 'New-ReleaseManifest.ps1') -Package $zip -PackageUrl 'https://github.com/rodrigoblergh/effects-studio/releases/download/v1/Effect-Studio-v1.zip' -Version '1.0' -Channel stable -MinAeMajor 26 -MaxAeMajor 27 -PrivateKey $key -Output $manifest
 $env:ES_FAKE_GH_LOG=$log;$env:ES_FAKE_GH_PACKAGE=$zip
 if((Get-Command gh.exe).Source -ne (Join-Path $root 'gh.exe')){throw 'Fake CLI is not first in PATH; refusing any publication.'}
 $publish=@{Package=$zip;Manifest=$manifest;PublicKey=$public;VersionTag='v1';Channel='stable';Confirm=$false}
 & (Join-Path $PSScriptRoot 'Publish-Release.ps1') @publish
 $calls=@(Get-Content -LiteralPath $log|ForEach-Object{,@($_|ConvertFrom-Json)})
 if($calls.Count -ne 7 -or ($calls[0] -join '|') -ne 'auth|status|--hostname|github.com'){throw 'CLI execution/argument binding failed.'}
 $uploads=@($calls|Where-Object{$_[0] -eq 'release' -and $_[1] -eq 'upload'})
 if($uploads.Count -ne 2 -or $uploads[0][2] -ne 'v1' -or $uploads[1][2] -ne 'update-v1-stable' -or $uploads[0] -contains '--clobber'){throw 'Package/feed ordering or immutability failed.'}
 [IO.File]::WriteAllText($log,'');$env:ES_FAKE_GH_EXISTING='1'
 & (Join-Path $PSScriptRoot 'Publish-Release.ps1') @publish
 $calls=@(Get-Content -LiteralPath $log|ForEach-Object{,@($_|ConvertFrom-Json)})
 $uploads=@($calls|Where-Object{$_[0] -eq 'release' -and $_[1] -eq 'upload'})
 if($uploads.Count -ne 1 -or $uploads[0][2] -ne 'update-v1-stable'){throw 'Matching package promotion failed.'}
 [IO.File]::WriteAllText($log,'');$env:ES_FAKE_GH_TAMPER='1';$rejected=$false
 try{& (Join-Path $PSScriptRoot 'Publish-Release.ps1') @publish}catch{$rejected=$true}
 if(!$rejected -or (Get-Content -LiteralPath $log -Raw) -match '"upload"'){throw 'Tampered remote package advanced feed.'}
 $originalManifest=Get-Content -LiteralPath $manifest -Raw
 foreach($line in @('missing','legacy-beta')){
  $envelope=$originalManifest|ConvertFrom-Json
  $data=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($envelope.payload))|ConvertFrom-Json
  if($line -eq 'missing'){$data.PSObject.Properties.Remove('releaseLine')}else{$data.releaseLine=$line}
  $bytes=[Text.Encoding]::UTF8.GetBytes(($data|ConvertTo-Json -Compress));$signed=@{payload=[Convert]::ToBase64String($bytes);signature=[Convert]::ToBase64String($rsa.SignData($bytes,[Security.Cryptography.CryptoConfig]::MapNameToOID('SHA256')))}
  [IO.File]::WriteAllText($manifest,($signed|ConvertTo-Json -Compress));[IO.File]::WriteAllText($log,'');$rejected=$false
  try{& (Join-Path $PSScriptRoot 'Publish-Release.ps1') @publish}catch{$rejected=$true}
  if(!$rejected -or (Get-Item -LiteralPath $log).Length -ne 0){throw 'Missing/wrong signed release line reached CLI.'}
 }
 [IO.File]::WriteAllText($manifest,$originalManifest)
 'PASS: real fake-gh.exe execution, all arguments preserved, package-before-feed, matching retry, tampered retry and signed missing/wrong release-line rejection. No network or publication.'
}finally{$rsa.Dispose();if(Test-Path -LiteralPath $key){[IO.File]::Delete($key)};$env:PATH=$oldPath;Remove-Item Env:ES_FAKE_GH_LOG,Env:ES_FAKE_GH_PACKAGE,Env:ES_FAKE_GH_EXISTING,Env:ES_FAKE_GH_TAMPER -ErrorAction SilentlyContinue}


