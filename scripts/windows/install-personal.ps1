#requires -RunAsAdministrator
param(
 [Parameter(Mandatory=$true)][string]$WireGuardMsi,
 [Parameter(Mandatory=$true)][string]$ClientConfig,
 [Parameter(Mandatory=$true)][string]$AuthorizedUserSid
)
$ErrorActionPreference = 'Stop'
if ($AuthorizedUserSid -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$') { throw 'One authorized user SID is required.' }
$msi = (Resolve-Path -LiteralPath $WireGuardMsi).Path
$signature = Get-AuthenticodeSignature -LiteralPath $msi
if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|, )O=WireGuard LLC(,|$)') { throw 'The official WireGuard LLC installer signature is required.' }
$config = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $ClientConfig).Path)
if ($config.Length -gt 8192) { throw 'Profile is too large.' }
$section = ''; $seen = @{}
foreach ($line in ($config -split '\r?\n')) {
 $line = $line.Trim()
 if (-not $line) { continue }
 if ($line -eq '[Interface]' -or $line -eq '[Peer]') {
  if ($seen.ContainsKey($line)) { throw 'Duplicate profile section.' }
  $seen[$line] = $true; $section = $line; continue
 }
 if ($line -notmatch '^([A-Za-z]+)\s*=\s*(.+)$') { throw 'Unsupported profile line.' }
 $name = $Matches[1]; $value = $Matches[2]; $key = "$section/$name"
 if ($seen.ContainsKey($key)) { throw 'Duplicate profile field.' }
 $seen[$key] = $value
 $allowed = if ($section -eq '[Interface]') { @('PrivateKey','Address','DNS','MTU') } elseif ($section -eq '[Peer]') { @('PublicKey','Endpoint','AllowedIPs','PersistentKeepalive') } else { @() }
 if ($name -cnotin $allowed) { throw 'Only canonical WireGuard fields are permitted.' }
}
foreach ($field in @('[Interface]/PrivateKey','[Peer]/PublicKey')) {
 try { $keyBytes = [Convert]::FromBase64String($seen[$field]) } catch { throw 'Invalid WireGuard key.' }
 if ($keyBytes.Length -ne 32) { throw 'Invalid WireGuard key length.' }
}
if ($seen['[Interface]/Address'] -ne '10.77.0.2/32, fd77:6474:7670::2/128' -or $seen['[Interface]/DNS'] -ne '1.1.1.1, 1.0.0.1' -or $seen['[Interface]/MTU'] -ne '1280' -or $seen['[Peer]/AllowedIPs'] -ne '0.0.0.0/0, ::/0' -or $seen['[Peer]/PersistentKeepalive'] -ne '25') { throw 'The generated personal profile is required.' }
$endpointParts = $seen['[Peer]/Endpoint'] -split ':(?=[^:]+$)'
if ($endpointParts.Count -ne 2) { throw 'Invalid endpoint.' }
$endpointAddress = $null; $endpointPort = 0
if (-not [System.Net.IPAddress]::TryParse($endpointParts[0].Trim('[',']'),[ref]$endpointAddress) -or -not [int]::TryParse($endpointParts[1],[ref]$endpointPort) -or $endpointPort -lt 1024 -or $endpointPort -gt 65535) { throw 'A fixed IP endpoint and valid port are required.' }
$install = Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'DuctTapeVPN'
$serviceName = 'WireGuardTunnel$DuctTape'
if ((Test-Path -LiteralPath $install) -or (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)) { throw 'Existing personal installation requires an upgrade review.' }
$installProcess = Start-Process msiexec.exe -ArgumentList @('/i', ('"' + $msi + '"'), '/qn', 'DO_NOT_LAUNCH=1') -Wait -PassThru -WindowStyle Hidden
if ($installProcess.ExitCode -notin @(0,3010)) { throw "WireGuard installation failed: $($installProcess.ExitCode)" }
$wireguard = Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'WireGuard\wireguard.exe'
$wg = Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'WireGuard\wg.exe'
foreach ($binary in @($wireguard,$wg)) {
 $sig = Get-AuthenticodeSignature -LiteralPath $binary
 if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch '(^|, )O=WireGuard LLC(,|$)') { throw 'Installed binary publisher verification failed.' }
}
New-Item -ItemType Directory -Path $install | Out-Null
icacls.exe $install /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Could not protect the profile directory.' }
$profile = Join-Path $install 'DuctTape.conf'
[System.IO.File]::WriteAllText($profile,$config,[System.Text.UTF8Encoding]::new($false))
try {
 & $wireguard /installtunnelservice $profile
 if ($LASTEXITCODE -ne 0) { throw 'Tunnel service installation failed.' }
 # Grant only query, start, stop and interrogate. No config changes or delete.
 $serviceDacl = "D:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCRPWPLO;;;$AuthorizedUserSid)"
 & sc.exe sdset $serviceName $serviceDacl | Out-Null
 if ($LASTEXITCODE -ne 0) { throw 'Could not assign narrow tunnel control rights.' }
 $ready = $false
 for ($attempt = 0; $attempt -lt 20; $attempt++) {
  Start-Sleep -Seconds 1
  & ping.exe -n 1 -w 500 10.77.0.1 | Out-Null
  $handshake = & $wg show DuctTape latest-handshakes 2>$null
  if ($LASTEXITCODE -eq 0 -and $handshake -match '\s([1-9][0-9]+)\s*$') { $ready = $true; break }
 }
 if (-not $ready) { throw 'No server handshake. Restoring the ordinary connection.' }
 $route = Find-NetRoute -RemoteIPAddress 1.1.1.1 | Select-Object -First 1
 if ($route.InterfaceAlias -ne 'DuctTape') { throw 'Internet traffic is not routed through DuctTape.' }
 Resolve-DnsName example.com -Server 1.1.1.1 -DnsOnly -ErrorAction Stop | Out-Null
 $trace = & curl.exe -4 --fail --silent --max-time 15 https://www.cloudflare.com/cdn-cgi/trace
 if ($LASTEXITCODE -ne 0 -or -not ($trace -match '^ip=')) { throw 'IPv4 internet verification failed.' }
 Stop-Service -Name $serviceName
 Set-Service -Name $serviceName -StartupType Manual
 Write-Output 'Installed and tested the personal tunnel. It is now OFF. Open Duct-Tape VPN and choose Connect.'
} catch {
 Stop-Service -Name $serviceName -ErrorAction SilentlyContinue
 Set-Service -Name $serviceName -StartupType Manual -ErrorAction SilentlyContinue
 throw
}
