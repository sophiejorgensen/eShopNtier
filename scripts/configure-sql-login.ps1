param(
    [Parameter(Mandatory = $true)]
    [string]$AppLogin,
    [string]$AppPassword,
    [ValidateSet("true", "false")]
    [string]$FinalizePermissions = "false"
)

$ErrorActionPreference = "Stop"
$connection = New-Object System.Data.SqlClient.SqlConnection(
    "Data Source=localhost;Initial Catalog=master;Integrated Security=SSPI;Encrypt=False;TrustServerCertificate=True;Connect Timeout=30"
)
try {
    $connection.Open()
    $command = $connection.CreateCommand()
    $command.CommandTimeout = 30
    $escapedLogin = $AppLogin.Replace("]", "]]")
    $loginLiteral = $AppLogin.Replace("'", "''")
    if ($FinalizePermissions -eq "true") {
        $command.CommandText = @"
IF IS_SRVROLEMEMBER(N'dbcreator', N'$loginLiteral') = 1
    ALTER SERVER ROLE [dbcreator] DROP MEMBER [$escapedLogin];
IF DB_ID(N'eShopDatabase') IS NULL
    THROW 51000, 'eShopDatabase was not initialized by the application.', 1;
ALTER AUTHORIZATION ON DATABASE::[eShopDatabase] TO [$escapedLogin];
"@
    }
    else {
        if ([string]::IsNullOrWhiteSpace($AppPassword)) {
            throw "An application SQL password is required during initial setup."
        }
        $escapedPassword = $AppPassword.Replace("'", "''")
        $command.CommandText = @"
IF NOT EXISTS (SELECT 1 FROM sys.sql_logins WHERE name = N'$loginLiteral')
    CREATE LOGIN [$escapedLogin] WITH PASSWORD = N'$escapedPassword', CHECK_POLICY = ON, CHECK_EXPIRATION = OFF;
IF IS_SRVROLEMEMBER(N'dbcreator', N'$loginLiteral') = 0
    ALTER SERVER ROLE [dbcreator] ADD MEMBER [$escapedLogin];
"@
    }
    [void]$command.ExecuteNonQuery()
}
finally {
    $connection.Dispose()
}
Write-Output "SQL Server application login configured."
