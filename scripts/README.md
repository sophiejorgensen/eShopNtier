# Azure SQL Server POC

These scripts deploy a small SQL Server 2022 Developer VM in Azure and run the
eShop application locally against it. The application is not deployed to Azure.
The VM is a development/test source instance for the user's later Modernize CLI
assessment, not a production database.

## Prerequisites

- Windows PowerShell and the .NET Framework 4.7.2 targeting/build tools required
  by `eShopDecomposed.sln`
- Azure CLI, Bicep, and an authenticated Azure account with permission to deploy
  resource groups, networking, and virtual machines in the approved subscription
- A public IPv4 address for the workstation running the application

## Deploy and run

From the repository root, run:

```powershell
.\scripts\deploy-azure-sqlserver.ps1
```

The script defaults to subscription `327a0648-13c5-43ae-833b-737dddad553a`,
region `eastus2`, resource group `rg-eshop-sql-poc`, and VM size
`Standard_D2as_v7`. It discovers the workstation's public IPv4 using `api.ipify.org`;
pass `-ClientIPv4 <address>` to specify it explicitly. The script refuses to
reuse an existing resource group.

The script deploys the subscription-scoped Bicep template in `infra\`, enables
SQL TCP/IP and mixed-mode authentication through Azure VM Run Command, and
creates a dedicated SQL login using managed Run Command with protected parameters.
It then builds the solution, initializes the
shared `eShopDatabase`, and launches the storefront and three services locally.
No RDP or SSH inbound rule is created.

After deployment, the local app is available at:

- Storefront: <http://localhost:5000>
- Catalog API: <http://localhost:5001>
- Discount API: <http://localhost:5002>
- Stock health: <http://localhost:5003/health>

Run `.\scripts\start-local.ps1` later to start the app again. It requires the
deployment's local connection files. App logs are written to `logs\`.

## Network and credentials

Inbound TCP 1433 is allowed only from the selected workstation IPv4 `/32` in
both the Azure network security group and Windows Firewall. If the workstation's
public IP changes, update the network rule and rerun the SQL configuration with
the new address before reconnecting.

The SQL login password and VM administrator password are stored as DPAPI-protected
XML files under `.local\`, bound to the Windows user who ran the deployment.
The deployment parameter JSON is temporary and removed when the script exits.
Do not copy or commit `.local\`. The app receives its SQL connection details
through environment variables when it starts. The service `App.config` files
also show the current POC VM as their default server; `ESHOP_SQL_SERVER` overrides
that default when set, including when `start-local.ps1` runs.

The POC encrypts SQL traffic but trusts the VM's server certificate without
validating its identity. Use a properly trusted certificate for production.

## Cost and lifecycle

The approved estimate for `Standard_D2as_v7` Windows compute is about $133.59 per
730-hour month. Managed disks, the public IP, outbound data, taxes, and
subscription-specific discounts and any security-service charges are additional. SQL Server Developer is free
for development/testing only. Compute charges continue while the VM is running;
deallocating it stops VM compute charges but does not remove disk or public-IP
charges.

To deallocate the VM while retaining its data:

```powershell
az vm deallocate --resource-group rg-eshop-sql-poc --name <vm-name>
```

To permanently remove the POC and its data, review the resource group first,
then delete it:

```powershell
az group delete --name rg-eshop-sql-poc --yes --no-wait
```

Deleting the resource group permanently deletes the VM, database files, network,
and public IP.
