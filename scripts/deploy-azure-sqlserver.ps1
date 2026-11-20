param(
    [string]$SubscriptionId = "327a0648-13c5-43ae-833b-737dddad553a",
    [string]$Location = "eastus2",
    [string]$ResourceGroupName = "rg-eshop-sql-poc",
    [string]$ClientIPv4
)

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$localDirectory = Join-Path $repositoryRoot ".local"
$templatePath = Join-Path $repositoryRoot "infra\main.bicep"
$deploymentParameterFile = $null
$sqlPassword = $null
$adminPassword = $null

function Invoke-Az([string[]]$Arguments) {
    & az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($Arguments[0])"
    }
}

function Get-AzValue([string[]]$Arguments) {
    $value = & az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI query failed: az $($Arguments[0])"
    }
    return ($value | Out-String).Trim()
}

try {
    if (-not $ClientIPv4) {
        $ClientIPv4 = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 10).Trim()
    }
    if ($ClientIPv4 -notmatch '^((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$') {
        throw "ClientIPv4 must be a valid IPv4 address."
    }
    $clientCidr = "$ClientIPv4/32"

    $currentSubscription = Get-AzValue @("account", "show", "--query", "id", "--output", "tsv")
    if ($currentSubscription -ne $SubscriptionId) {
        Invoke-Az @("account", "set", "--subscription", $SubscriptionId)
    }

    $groupExists = Get-AzValue @("group", "exists", "--name", $ResourceGroupName)
    if ($groupExists -eq "true") {
        throw "Resource group '$ResourceGroupName' already exists. Review it and choose a new name before provisioning."
    }

    $suffix = [Guid]::NewGuid().ToString("N").Substring(0, 6)
    $vmName = "eshopsql-$suffix"
    $dnsLabel = $vmName
    $sqlPassword = ([Guid]::NewGuid().ToString("N") + "Aa1!")
    $adminPassword = ([Guid]::NewGuid().ToString("N") + "Aa1!")

    if (-not (Test-Path $templatePath)) {
        throw "The Bicep deployment template was not found: $templatePath"
    }

    $sqlPasswordFile = Join-Path $localDirectory "azure-sqlserver-password.xml"
    $adminPasswordFile = Join-Path $localDirectory "azure-sqlserver-vm-admin-password.xml"
    $endpointFile = Join-Path $localDirectory "azure-sqlserver-endpoint.txt"
    foreach ($path in @($sqlPasswordFile, $adminPasswordFile, $endpointFile)) {
        if (Test-Path $path) {
            throw "Local Azure SQL connection file already exists: $path. Review it before provisioning."
        }
    }

    $secureSqlPassword = ConvertTo-SecureString $sqlPassword -AsPlainText -Force
    $secureAdminPassword = ConvertTo-SecureString $adminPassword -AsPlainText -Force
    New-Item -ItemType Directory -Force -Path $localDirectory | Out-Null
    $secureSqlPassword | Export-Clixml -Path $sqlPasswordFile
    $secureAdminPassword | Export-Clixml -Path $adminPasswordFile

    $deploymentParameterFile = Join-Path $localDirectory "$vmName-deployment-parameters.tmp.json"
    $deploymentParameters = @{
        location = @{ value = $Location }
        resourceGroupName = @{ value = $ResourceGroupName }
        vmName = @{ value = $vmName }
        dnsLabel = @{ value = $dnsLabel }
        adminUsername = @{ value = "eshopadmin" }
        adminPassword = @{ value = $adminPassword }
        sourceAddress = @{ value = $ClientIPv4 }
        vmSize = @{ value = "Standard_D2as_v7" }
    }
    $deploymentParameters | ConvertTo-Json -Depth 4 |
        Set-Content -Path $deploymentParameterFile -Encoding UTF8

    $deploymentJson = & az deployment sub create `
        --name "$vmName-deployment" `
        --location $Location `
        --subscription $SubscriptionId `
        --template-file $templatePath `
        --parameters "@$deploymentParameterFile" `
        --only-show-errors `
        --output json
    if ($LASTEXITCODE -ne 0) {
        throw "Azure SQL Server infrastructure deployment failed."
    }
    $deployment = ($deploymentJson | Out-String) | ConvertFrom-Json
    $fqdn = $deployment.properties.outputs.sqlFqdn.value
    if ([string]::IsNullOrWhiteSpace($fqdn)) {
        throw "Azure deployment completed without returning a SQL Server DNS name."
    }

    & (Join-Path $PSScriptRoot "configure-azure-sqlserver.ps1") `
        -VmName $vmName -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName `
        -Location $Location -ClientIPv4 $ClientIPv4 -Endpoint $fqdn

    Write-Host ""
    Write-Host "Azure SQL Server is deployed and the local eShop app is connected:"
    Write-Host "  Resource group: $ResourceGroupName"
    Write-Host "  VM:             $vmName ($Location, Standard_D2as_v7)"
    Write-Host "  SQL endpoint:   $fqdn,1433"
    Write-Host "  Database:       eShopDatabase"
    Write-Host "  Allowed source: $clientCidr"
    Write-Host "  App:            http://localhost:5000"
    Write-Host "The VM's SQL login password is stored in .local, protected for this Windows user."
}
finally {
    if ($deploymentParameterFile -and (Test-Path $deploymentParameterFile)) {
        Remove-Item -Path $deploymentParameterFile -Force
    }
    $sqlPassword = $null
    $adminPassword = $null
}
