# Azure CLI Helper

This folder contains `AzureCLI.ps1`, a PowerShell helper for Azure CLI authentication, subscription/tenant inspection, and free-tier environment setup.

## How to use

Load the helper in PowerShell:

```powershell
. "c:\Users\bruno\code\research-algorithms\Azure\AzureCLI.ps1"
```

Create a client object:

```powershell
$client = New-AzureCliClient
```

## Available commands

### Authentication
- `Connect-AzureAccount` — sign in to Azure if not already authenticated
  - `-UseDeviceCode` — use device-code auth
  - `-TenantId <id>` — login to a specific tenant
  - `-AllowNoSubscriptions` — allow login even without subscriptions
  - `-Force` — force a fresh login
- `Get-AzureLoggedInAccount` — returns current signed-in account info
- `GetLoggedInAccount()` — same via client object
- `IsAuthenticated()` — checks whether CLI is already signed in

### Tenant and subscription inspection
- `Get-AzureTenants` — list Azure tenants
- `Get-AzureSubscriptions` — list subscriptions for the signed-in account
- `Get-AzureSubscriptionData -SubscriptionId <id>` — get full subscription data, or all subscriptions when no ID is provided
- `Get-AzureSubscriptionDetails -SubscriptionId <id>` — show selected subscription details

### Free-tier helpers
- `Get-AzureFreeTierStatus -SubscriptionId <id>` — inspect whether a subscription appears to be free/trial
- `Set-AzureAccountFreeTier -SubscriptionId <id>` — validate free-tier status and print next steps
- `Setup-AzureFreeTierEnvironment -ResourceGroupName <name> -Location <location>` — create a resource group, App Service plan, and storage account in a selected subscription

## Example usage

```powershell
# Load helper
. "c:\Users\bruno\code\research-algorithms\Azure\AzureCLI.ps1"

# Authenticate if needed
Connect-AzureAccount -UseDeviceCode -AllowNoSubscriptions

# Check current login state
Get-AzureLoggedInAccount

# List tenants and subscriptions
Get-AzureTenants
Get-AzureSubscriptions

# Setup a free-tier environment
Setup-AzureFreeTierEnvironment -ResourceGroupName 'free-tier-rg' -Location 'eastus2'
```

## Notes
- The helper uses Azure CLI under the hood.
- If Azure CLI is already authenticated, it will skip re-login.
- For automation, prefer service principals instead of interactive user login.
