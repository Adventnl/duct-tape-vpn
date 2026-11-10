#requires -RunAsAdministrator
$ErrorActionPreference='Stop'
# Intentional OFF through the broker must succeed before clean removal. Persistent filters protect crash states.
$pipe=[System.IO.Pipes.NamedPipeClientStream]::new('.','DuctTapeVPN',[System.IO.Pipes.PipeDirection]::InOut)
$pipe.Connect(5000)
$command=[System.Text.Encoding]::ASCII.GetBytes('OFF');$pipe.Write($command,0,$command.Length)
$buffer=New-Object byte[] 1024;$n=$pipe.Read($buffer,0,$buffer.Length);$pipe.Dispose()
if([System.Text.Encoding]::ASCII.GetString($buffer,0,$n) -ne 'OK'){throw 'OFF failed: inspect owned WFP filters before uninstall'}
Stop-Service DuctTapeAgent
sc.exe delete DuctTapeAgent
sc.exe delete 'WireGuardTunnel$dtvpn'
Write-Output 'Owned services removed. Preserve encrypted credentials/backups until you explicitly delete the installation and Credential Manager entries.'
