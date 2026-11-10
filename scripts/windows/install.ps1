#requires -RunAsAdministrator
param(
 [Parameter(Mandatory=$true)][string]$VerifiedArtifactDirectory,
 [Parameter(Mandatory=$true)][string]$AuthorizedUserSid,
 [Parameter(Mandatory=$true)][System.Net.IPAddress]$EndpointIPv4,
 [Parameter(Mandatory=$true)][ValidateRange(1,65535)][int]$EndpointPort,
 [Parameter(Mandatory=$true)][string]$GeneratedConfig,
 [Parameter(Mandatory=$true)][string]$ApprovedManifest
)
$ErrorActionPreference='Stop'
# Offline TUF/Owner verification happens before this action. Bind installation to exact verified bytes.
$manifest=Get-Content -Raw $ApprovedManifest | ConvertFrom-Json
$install=Join-Path $env:ProgramFiles 'DuctTapeVPN'
if(Test-Path $install){throw 'Existing installation: review an upgrade/rollback plan rather than overwrite'}
if($AuthorizedUserSid -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$'){throw 'A single local user SID is required'}
if($EndpointIPv4.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork){throw 'This Windows activation path currently requires IPv4 transport'}
$files=@('dtvpn-agent.exe','tunnel.dll','wireguard.dll')
foreach($name in $files){
 $file=Join-Path $VerifiedArtifactDirectory $name
 if((Get-FileHash $file -Algorithm SHA256).Hash.ToLowerInvariant() -ne $manifest.$name){throw "Hash mismatch: $name"}
 $signature=Get-AuthenticodeSignature $file
 if($signature.Status -ne 'Valid'){throw "Valid publisher signature required: $name"}
}
# Reject all imported script hooks; accept only generated canonical WireGuard fields.
$config=Get-Content -Raw $GeneratedConfig
if($config.Length -gt 8192 -or $config -match '(?im)^\s*(PreUp|PostUp|PreDown|PostDown|Table|ExcludedApplications)\s*='){throw 'Unsupported configuration'}
if($config -notmatch '(?im)^AllowedIPs\s*=\s*0\.0\.0\.0/0,\s*::/0\s*$'){throw 'Strict dual-stack tunnel routing required'}
New-Item -ItemType Directory $install | Out-Null
icacls $install /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'BUILTIN\Administrators:(OI)(CI)F' | Out-Null
foreach($name in $files){Copy-Item (Join-Path $VerifiedArtifactDirectory $name) (Join-Path $install $name)}
$configPath=Join-Path $install 'dtvpn.conf'
[System.IO.File]::WriteAllText($configPath,$config,[System.Text.UTF8Encoding]::new($false))
New-Item 'HKLM:\SOFTWARE\DuctTapeVPN' -Force | Out-Null
$bytes=$EndpointIPv4.GetAddressBytes();[uint32]$hostAddress=([uint32]$bytes[0]*16777216)+([uint32]$bytes[1]*65536)+([uint32]$bytes[2]*256)+[uint32]$bytes[3]
New-ItemProperty 'HKLM:\SOFTWARE\DuctTapeVPN' RemoteIPv4 -Value $hostAddress -PropertyType DWord | Out-Null
New-ItemProperty 'HKLM:\SOFTWARE\DuctTapeVPN' RemotePort -Value $EndpointPort -PropertyType DWord | Out-Null
New-ItemProperty 'HKLM:\SOFTWARE\DuctTapeVPN' PipeSDDL -Value "D:P(A;;GA;;;SY)(A;;GA;;;BA)(A;;GRGW;;;$AuthorizedUserSid)" -PropertyType String | Out-Null
$exe=Join-Path $install 'dtvpn-agent.exe'
New-Service -Name 'WireGuardTunnel$dtvpn' -BinaryPathName "`"$exe`" /tunnel `"$configPath`"" -StartupType Manual -DependsOn Nsi,Tcpip
sc.exe sidtype 'WireGuardTunnel$dtvpn' unrestricted
if($LASTEXITCODE -ne 0){throw 'Tunnel service SID configuration failed'}
New-Service -Name DuctTapeAgent -BinaryPathName "`"$exe`"" -StartupType Automatic -DependsOn BFE
sc.exe failure DuctTapeAgent reset= 86400 actions= restart/2000/restart/5000/restart/15000
Write-Output 'Installed with desired OFF. Review service ACLs and run the Windows acceptance matrix before use.'
