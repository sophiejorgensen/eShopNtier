$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$localDirectory = Join-Path $repositoryRoot ".local"
$passwordFile = Join-Path $localDirectory "azure-sqlserver-password.xml"
$serverFile = Join-Path $localDirectory "azure-sqlserver-endpoint.txt"
$logDirectory = Join-Path $repositoryRoot "logs"
$passwordPointer = [IntPtr]::Zero
$startedProcesses = @()
$completed = $false

function Assert-PortAvailable([int]$Port) {
    if (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue) {
        throw "Port $Port is already in use. Stop the process using it, then rerun this script."
    }
}

function Start-App([string]$Name, [int]$Port) {
    $outputDirectory = Join-Path $repositoryRoot "src\$Name\bin\Debug\net472"
    $executable = Join-Path $outputDirectory "$Name.exe"
    if (-not (Test-Path $executable)) {
        throw "Build output not found: $executable"
    }

    $process = Start-Process -FilePath $executable -WorkingDirectory $outputDirectory `
        -RedirectStandardOutput (Join-Path $logDirectory "$Name.out.log") `
        -RedirectStandardError (Join-Path $logDirectory "$Name.err.log") -PassThru
    $script:startedProcesses += $process
    Write-Host "$Name started (PID $($process.Id), port $Port)."
}

function Wait-ForHttp([string]$Name, [string]$Uri) {
    $lastError = "No successful response."
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri $Uri -TimeoutSec 3 -UseBasicParsing
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400) {
                return
            }
            $lastError = "HTTP $($response.StatusCode)"
        }
        catch {
            $lastError = $_.Exception.Message
        }
        Start-Sleep -Seconds 2
    }

    throw "$Name did not become ready at $Uri. $lastError"
}

try {
    if (-not (Test-Path $passwordFile) -or -not (Test-Path $serverFile)) {
        throw "Azure SQL connection details are missing. Run scripts\deploy-azure-sqlserver.ps1 first."
    }
    foreach ($port in @(5000, 5001, 5002, 5003)) {
        Assert-PortAvailable $port
    }

    $serverName = (Get-Content -Path $serverFile -Raw).Trim()
    $securePassword = Import-Clixml -Path $passwordFile
    $passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $sqlPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)

    $env:ESHOP_SQL_SERVER = "$serverName,1433"
    $env:ESHOP_SQL_USER = "eshop_app"
    $env:ESHOP_SQL_PASSWORD = $sqlPassword

    New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
    dotnet build (Join-Path $repositoryRoot "eShopDecomposed.sln")
    if ($LASTEXITCODE -ne 0) {
        throw "The solution build failed."
    }

    Start-App "Catalog.Service" 5001
    Wait-ForHttp "Catalog.Service" "http://localhost:5001/api/catalog/items"
    Start-App "Discount.Service" 5002
    Start-App "Stock.Worker" 5003
    Start-App "eShop.WebFrontend" 5000

    Wait-ForHttp "Discount.Service" "http://localhost:5002/api/discounts"
    Wait-ForHttp "Stock.Worker" "http://localhost:5003/health"
    Wait-ForHttp "eShop.WebFrontend" "http://localhost:5000/"

    $completed = $true
    Write-Host ""
    Write-Host "eShop is running against Azure SQL Server:"
    Write-Host "  Storefront:      http://localhost:5000"
    Write-Host "  Catalog API:     http://localhost:5001"
    Write-Host "  Discount API:    http://localhost:5002"
    Write-Host "  Stock health:    http://localhost:5003/health"
    Write-Host "  SQL Server:      $serverName,1433 (eShopDatabase)"
    Write-Host "Logs: $logDirectory"
}
finally {
    Remove-Item Env:ESHOP_SQL_SERVER -ErrorAction SilentlyContinue
    Remove-Item Env:ESHOP_SQL_USER -ErrorAction SilentlyContinue
    Remove-Item Env:ESHOP_SQL_PASSWORD -ErrorAction SilentlyContinue
    if ($passwordPointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    }
    $sqlPassword = $null

    if (-not $completed) {
        foreach ($process in $startedProcesses) {
            if (Get-Process -Id $process.Id -ErrorAction SilentlyContinue) {
                Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
            }
        }
    }
}
