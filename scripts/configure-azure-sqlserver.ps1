param(
    [Parameter(Mandatory = $true)]
    [string]$VmName,
    [Parameter(Mandatory = $true)]
    [string]$SubscriptionId,
    [string]$ResourceGroupName = "rg-eshop-sql-poc",
    [string]$Location = "eastus2",
    [Parameter(Mandatory = $true)]
    [string]$ClientIPv4,
    [Parameter(Mandatory = $true)]
    [string]$Endpoint
)

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$localDirectory = Join-Path $repositoryRoot ".local"
$loginScript = Get-Content (Join-Path $PSScriptRoot "configure-sql-login.ps1") -Raw
$encodedScript = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($loginScript))
$scriptContent = 'param([string]$AppLogin,[string]$AppPassword,[string]$FinalizePermissions); & ([scriptblock]::Create([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String("{0}")))) -AppLogin $AppLogin -AppPassword $AppPassword -FinalizePermissions $FinalizePermissions' -f $encodedScript
$adminPointer = [IntPtr]::Zero
$sqlPointer = [IntPtr]::Zero

function Invoke-ManagedSqlSetup([string]$Phase) {
    $name = "eshop-$Phase-$([Guid]::NewGuid().ToString('N').Substring(0, 8))"
    $token = az account get-access-token --subscription $SubscriptionId --query accessToken -o tsv
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to get an Azure management token."
    }

    $properties = @{
        source = @{ script = $scriptContent }
        runAsUser = "eshopadmin"
        runAsPassword = $adminPassword
        asyncExecution = $false
        timeoutInSeconds = 600
        treatFailureAsDeploymentFailure = $true
        parameters = @(
            @{ name = "AppLogin"; value = "eshop_app" }
            @{ name = "FinalizePermissions"; value = $(if ($Phase -eq "finalize") { "true" } else { "false" }) }
        )
    }
    if ($Phase -eq "setup") {
        $properties.protectedParameters = @(@{ name = "AppPassword"; value = $sqlPassword })
    }

    $uri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Compute/virtualMachines/$VmName/runCommands/$($name)?api-version=2025-04-01"
    $body = @{ location = $Location; properties = $properties } | ConvertTo-Json -Depth 8
    try {
        Invoke-RestMethod -Method Put -Uri $uri -Headers @{ Authorization = "Bearer $token" } `
            -ContentType "application/json" -Body $body | Out-Null
    }
    finally {
        $token = $null
        $body = $null
    }

    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        $json = az vm run-command show --resource-group $ResourceGroupName --vm-name $VmName `
            --name $name --instance-view --subscription $SubscriptionId --only-show-errors -o json
        if ($LASTEXITCODE -ne 0) {
            throw "Could not read SQL setup status for $name."
        }
        $status = (($json | Out-String) | ConvertFrom-Json).instanceView
        if ($status.executionState -eq "Succeeded" -and $status.exitCode -eq 0 -and
            $status.output -match "SQL Server application login configured\.") {
            return
        }
        if ($status.executionState -in @("Succeeded", "Failed", "TimedOut", "Canceled")) {
            throw "SQL setup failed: $($status.executionMessage) $($status.error) $($status.output)"
        }
        Start-Sleep -Seconds 5
    }
    throw "SQL setup did not complete in time. Inspect Azure Run Command $name before retrying."
}

try {
    $adminSecure = Import-Clixml (Join-Path $localDirectory "azure-sqlserver-vm-admin-password.xml")
    $sqlSecure = Import-Clixml (Join-Path $localDirectory "azure-sqlserver-password.xml")
    $adminPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($adminSecure)
    $sqlPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sqlSecure)
    $adminPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($adminPointer)
    $sqlPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($sqlPointer)

    $networkScript = Join-Path $PSScriptRoot "configure-sql-vm.ps1"
    $networkResult = az vm run-command invoke --resource-group $ResourceGroupName --name $VmName `
        --subscription $SubscriptionId --command-id RunPowerShellScript --scripts "@$networkScript" `
        --parameters "SourceAddress=$ClientIPv4/32" --only-show-errors -o json
    if ($LASTEXITCODE -ne 0) {
        throw "Azure VM network configuration failed."
    }
    $messages = (($networkResult | Out-String) | ConvertFrom-Json).value
    if (-not ($messages | Where-Object { $_.message -match 'SQL Server TCP configured\.' })) {
        throw "SQL Server network configuration failed: $(($messages | ForEach-Object { $_.message }) -join "`n")"
    }
    Invoke-ManagedSqlSetup "setup"
    Set-Content -Path (Join-Path $localDirectory "azure-sqlserver-endpoint.txt") -Value $Endpoint -NoNewline
    & (Join-Path $PSScriptRoot "start-local.ps1")
    Invoke-ManagedSqlSetup "finalize"
}
finally {
    if ($adminPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($adminPointer)
    }
    if ($sqlPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($sqlPointer)
    }
    $adminPassword = $null
    $sqlPassword = $null
}
