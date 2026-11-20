param(
    [Parameter(Mandatory = $true)]
    [string]$SourceAddress
)

$ErrorActionPreference = "Stop"
$instanceNames = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL"
$instanceId = $instanceNames.MSSQLSERVER
if (-not $instanceId) {
    throw "The default SQL Server instance was not found."
}

$instancePath = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\MSSQLServer"
$tcpPath = Join-Path $instancePath "SuperSocketNetLib\Tcp"
$ipAllPath = Join-Path $tcpPath "IPAll"
Set-ItemProperty -Path $tcpPath -Name Enabled -Value 1
Set-ItemProperty -Path $ipAllPath -Name TcpDynamicPorts -Value ""
Set-ItemProperty -Path $ipAllPath -Name TcpPort -Value "1433"
Set-ItemProperty -Path $instancePath -Name LoginMode -Value 2

$firewallRuleName = "eShop SQL from approved client"
Get-NetFirewallRule -DisplayName $firewallRuleName -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule
New-NetFirewallRule -DisplayName $firewallRuleName -Direction Inbound -Action Allow `
    -Protocol TCP -LocalPort 1433 -RemoteAddress $SourceAddress -Profile Any | Out-Null

Restart-Service -Name MSSQLSERVER -Force
for ($attempt = 0; $attempt -lt 60; $attempt++) {
    if ((Get-Service -Name MSSQLSERVER).Status -eq "Running" -and
        (Test-NetConnection -ComputerName localhost -Port 1433 -InformationLevel Quiet)) {
        Write-Output "SQL Server TCP configured."
        return
    }
    Start-Sleep -Seconds 2
}
throw "SQL Server did not restart with TCP enabled on port 1433."
