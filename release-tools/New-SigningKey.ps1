[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$PrivateDirectory,
      [Parameter(Mandatory=$true)][string]$PublicKeyOutput)
$ErrorActionPreference='Stop'
$privateRoot=[IO.Path]::GetFullPath($PrivateDirectory)
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..')).TrimEnd('\')+'\'
if($privateRoot.StartsWith($workspace,[StringComparison]::OrdinalIgnoreCase)){throw 'Private key storage must be outside the source/package workspace.'}
if(Test-Path -LiteralPath $privateRoot){throw 'Choose a new private directory; existing paths are never overwritten.'}
$publicPath=[IO.Path]::GetFullPath($PublicKeyOutput)
if(Test-Path -LiteralPath $publicPath){throw 'Public key output already exists.'}
# Restrict the directory before creating any key material inside it.
$identity=[Security.Principal.WindowsIdentity]::GetCurrent().User
$acl=New-Object Security.AccessControl.DirectorySecurity
$acl.SetOwner($identity)
$acl.SetAccessRuleProtection($true,$false)
$rule=New-Object Security.AccessControl.FileSystemAccessRule($identity,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
$acl.AddAccessRule($rule)
[IO.Directory]::CreateDirectory($privateRoot) | Out-Null
Set-Acl -LiteralPath $privateRoot -AclObject $acl
$rsa=New-Object Security.Cryptography.RSACryptoServiceProvider(4096)
$rsa.PersistKeyInCsp=$false
try {
 $utf8=New-Object Text.UTF8Encoding($false)
 [IO.File]::WriteAllText((Join-Path $privateRoot 'signing-key.xml'),$rsa.ToXmlString($true),$utf8)
 [IO.File]::WriteAllText($publicPath,$rsa.ToXmlString($false),$utf8)
} finally {$rsa.Dispose()}
Write-Output 'Created owner-restricted private key and public key. Back up the private key securely; never put it in a release ZIP.'
