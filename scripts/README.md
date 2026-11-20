# Azure SQL Server POC

These scripts create a SQL Server 2022 Developer VM in Azure, initialize a new
eShop database, and run the application on your Windows computer against it.
They do not deploy the application to Azure, migrate an existing database, or
set up the separate Modernize SQL assessment login. This is a development/test
POC, not a production deployment.

## Prerequisites

- Windows, Git, PowerShell, a .NET SDK, and the .NET Framework 4.7.2 developer
  pack (targeting pack). The build restores NuGet packages from configured feeds.
- Azure CLI with Bicep installed (`az bicep install`), and an Azure subscription
  where you can create resource groups, networking, VMs, deployments, and VM
  Run Commands. SQL Server 2022 Developer and the selected VM size must be
  available in the chosen region; quota and subscription policy must permit them.
- Internet access and a public IPv4 address for this computer. Ports 5000-5003
  must be free locally, and your network must allow outbound SQL TCP port 1433.
- An Azure budget for the VM, disks, and networking. Developer edition is
  licensed for development/testing only.

## Deploy and run

Clone the repository and switch to the branch containing these scripts. In
PowerShell at the repository root, sign in and choose **your own** subscription:

```powershell
git clone https://github.com/sophiejorgensen/eShopNtier.git
Set-Location eShopNtier
git switch sojorgensen/sqlserver
az login
az account list --output table
az bicep install
.\scripts\deploy-azure-sqlserver.ps1 -SubscriptionId "<your-subscription-id>"
```

Replace the placeholder with your subscription ID. The script targets that
subscription explicitly and does not change the Azure CLI's active subscription.
It defaults to region `eastus2`, resource group `rg-eshop-sql-poc`, and VM size
`Standard_D2as_v7`. Use `-Location <region>` or
`-ResourceGroupName <new-name>` to change the first two. The script refuses to
reuse an existing resource group. It discovers your public IPv4 using
`api.ipify.org`; pass `-ClientIPv4 <address>` to specify it explicitly instead.
Review the expected cost before running: this creates billable Azure resources.

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
deployment's local connection files and must be run as the same Windows user on
the same computer. Start the Azure VM first if it was deallocated. App logs are
written to `logs\`. The app uses sample data initialized on first deployment;
no database backup or data from another deployment is copied.

If provisioning fails, resources already created may continue to incur charges.
Inspect the Azure resource group, VM Run Command results, and app logs before
retrying. The deployment script deliberately refuses to overwrite an existing
resource group or local connection files; don't delete either until you have
reviewed whether you need their contents.

## Network and credentials

Inbound TCP 1433 is allowed only from the selected workstation IPv4 `/32` in
both the Azure network security group and Windows Firewall. If the workstation's
public IP changes, both rules need updating before reconnecting. The app
connection files are specific to the machine and Windows user that deployed it;
another user should deploy their own POC rather than copy credentials.

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
subscription-specific discounts and any security-service charges are additional.
Pricing and VM availability vary by region and subscription. Compute charges continue while the VM is running;
deallocating it stops VM compute charges but does not remove disk or public-IP
charges.

To deallocate the VM while retaining its data:

```powershell
az vm deallocate --subscription <your-subscription-id> --resource-group <resource-group> --name <vm-name>
```

To permanently remove the POC and its data, review the resource group first,
then delete it:

```powershell
az group delete --subscription <your-subscription-id> --name <resource-group> --yes --no-wait
```

Deleting the resource group permanently deletes the VM, database files, network,
and public IP.
