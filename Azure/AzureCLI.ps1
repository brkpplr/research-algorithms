<#
.SYNOPSIS
  Azure CLI helper for authentication, subscription inspection, and free-tier environment setup.
.DESCRIPTION
  Provides reusable PowerShell functions that wrap Azure CLI and Azure Resource Manager operations.
  Supports login checks, tenant/subscription listing, and basic free-tier resource provisioning.
.NOTES
  Requires Azure CLI installed and available in PATH.
#>

function Ensure-AzureCLI {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'Azure CLI is not installed. Install it first from https://learn.microsoft.com/cli/azure/install-azure-cli'
    }
}

function Invoke-AzureCli {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    Ensure-AzureCLI
    $output = az @Arguments 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: $($output -join "`n")"
    }

    return $output
}

function ConvertFrom-AzureJson {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Json
    )

    if (-not $Json) {
        return $null
    }

    if ($Json -is [System.Array]) {
        $Json = $Json -join "`n"
    }

    return $Json | ConvertFrom-Json
}

function Get-AzureLoggedInAccount {
    Ensure-AzureCLI

    try {
        $output = Invoke-AzureCli -Arguments @('account', 'show', '--query', '{id:id,name:name,tenantId:tenantId,user:user,state:state}', '-o', 'json')
        return ConvertFrom-AzureJson -Json $output
    }
    catch {
        return $null
    }
}

function Connect-AzureAccount {
    param(
        [switch]$UseDeviceCode,
        [string]$TenantId,
        [switch]$AllowNoSubscriptions,
        [switch]$Force
    )

    Ensure-AzureCLI
    $currentAccount = Get-AzureLoggedInAccount

    if ($currentAccount -and -not $Force) {
        if ($currentAccount.user -and $currentAccount.user.name) {
            Write-Host "Azure CLI is already authenticated as $($currentAccount.user.name) in tenant $($currentAccount.tenantId)."
        }
        else {
            Write-Host "Azure CLI is already authenticated in tenant $($currentAccount.tenantId)."
        }

        return $currentAccount
    }

    Write-Host 'Signing in to Azure...'

    $arguments = @('login')

    if ($UseDeviceCode) {
        $arguments += '--use-device-code'
    }
    if ($TenantId) {
        $arguments += @('--tenant', $TenantId)
    }
    if ($AllowNoSubscriptions) {
        $arguments += '--allow-no-subscriptions'
    }

    Invoke-AzureCli -Arguments $arguments | Out-Null
    return Get-AzureLoggedInAccount
}

function Get-AzureAccessToken {
    Ensure-AzureCLI
    $token = Invoke-AzureCli -Arguments @('account', 'get-access-token', '--resource', 'https://management.azure.com/', '--query', 'accessToken', '-o', 'tsv')

    if (-not $token) {
        throw 'Unable to retrieve Azure access token. Please login with az login.'
    }

    return $token -join "`n"
}

function Invoke-AzureManagementApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('GET','POST','PUT','PATCH','DELETE')]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter()]
        [object]$Body,

        [Parameter()]
        [hashtable]$Headers = @{}
    )

    $token = Get-AzureAccessToken
    $headers['Authorization'] = "Bearer $token"
    $headers['Content-Type'] = 'application/json'

    try {
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -Body ($Body | ConvertTo-Json -Depth 10) -ErrorAction Stop
    }
    catch {
        throw "Azure management API request failed: $($_.Exception.Message)"
    }
}

function Get-AzureSubscriptions {
    Ensure-AzureCLI
    $output = Invoke-AzureCli -Arguments @('account', 'list', '--query', '[].{id:id,name:name,state:state,tenantId:tenantId}', '-o', 'json')
    return ConvertFrom-AzureJson -Json $output
}

function Get-AzureSubscriptionData {
    param(
        [string]$SubscriptionId
    )

    Ensure-AzureCLI

    if ($SubscriptionId) {
        $output = Invoke-AzureCli -Arguments @('account', 'show', '--subscription', $SubscriptionId, '-o', 'json')
        return ConvertFrom-AzureJson -Json $output
    }

    $output = Invoke-AzureCli -Arguments @('account', 'list', '--all', '-o', 'json')
    return ConvertFrom-AzureJson -Json $output
}

function Get-AzureTenants {
    Ensure-AzureCLI
    $output = Invoke-AzureCli -Arguments @('account', 'tenant', 'list', '--query', '[].{id:id,tenantId:tenantId,displayName:displayName,defaultDomain:defaultDomain,tenantCategory:tenantCategory}', '-o', 'json')
    return ConvertFrom-AzureJson -Json $output
}

function Select-AzureSubscription {
    param(
        [string]$SubscriptionId
    )

    if ($SubscriptionId) {
        Invoke-AzureCli -Arguments @('account', 'set', '--subscription', $SubscriptionId) | Out-Null
        return
    }

    $subscriptions = Get-AzureSubscriptions
    if (-not $subscriptions) {
        throw 'No Azure subscriptions were found for the current account.'
    }

    if ($subscriptions.Count -eq 1) {
        Invoke-AzureCli -Arguments @('account', 'set', '--subscription', $subscriptions[0].id) | Out-Null
        Write-Host "Selected subscription: $($subscriptions[0].name) ($($subscriptions[0].id))"
        return
    }

    Write-Host 'Available subscriptions:'
    for ($i = 0; $i -lt $subscriptions.Count; $i++) {
        Write-Host "[$i] $($subscriptions[$i].name) ($($subscriptions[$i].id)) - $($subscriptions[$i].state)"
    }

    $selection = Read-Host 'Enter subscription index to select'
    if (-not [int]::TryParse($selection, [ref]$null) -or $selection -lt 0 -or $selection -ge $subscriptions.Count) {
        throw 'Invalid selection.'
    }

    $selected = $subscriptions[$selection]
    Invoke-AzureCli -Arguments @('account', 'set', '--subscription', $selected.id) | Out-Null
    Write-Host "Selected subscription: $($selected.name) ($($selected.id))"
}

function Get-AzureSubscriptionDetails {
    param(
        [string]$SubscriptionId
    )

    Ensure-AzureCLI
    if ($SubscriptionId) {
        Select-AzureSubscription -SubscriptionId $SubscriptionId
    }

    $output = Invoke-AzureCli -Arguments @('account', 'show', '--query', '{id:id,name:name,state:state,tenantId:tenantId,environmentName:environmentName,homeTenantId:homeTenantId}', '-o', 'json')
    return ConvertFrom-AzureJson -Json $output
}

function Get-AzureFreeTierStatus {
    param(
        [string]$SubscriptionId
    )

    $details = Get-AzureSubscriptionDetails -SubscriptionId $SubscriptionId
    if (-not $details) {
        throw 'Unable to retrieve subscription details.'
    }

    $subscriptionUri = "https://management.azure.com/subscriptions/$($details.id)?api-version=2020-01-01"
    $subscriptionData = Invoke-AzureManagementApi -Method GET -Uri $subscriptionUri

    $offerType = $subscriptionData.offerType
    $displayName = $subscriptionData.displayName
    $freeTier = $false

    if ($offerType -match 'Free|Trial|MS-AZR-0017P|MS-AZR-0148P') {
        $freeTier = $true
    }

    return [PSCustomObject]@{
        SubscriptionId = $details.id
        Name = $displayName
        OfferType = $offerType
        IsFreeTier = $freeTier
        Raw = $subscriptionData
    }
}

function Set-AzureAccountFreeTier {
    param(
        [string]$SubscriptionId
    )

    Ensure-AzureCLI
    Connect-AzureAccount
    Select-AzureSubscription -SubscriptionId $SubscriptionId

    $status = Get-AzureFreeTierStatus -SubscriptionId $SubscriptionId
    Write-Host "Subscription: $($status.Name) ($($status.SubscriptionId))"
    Write-Host "Offer Type: $($status.OfferType)"

    if ($status.IsFreeTier) {
        Write-Host 'This subscription already appears to be a free-tier or trial subscription.'
        return $status
    }

    Write-Warning 'Azure does not allow converting an existing paid subscription into a free-tier subscription through the CLI. The free account offer must be created through Azure signup flows or support channels.'
    Write-Host 'Next steps:'
    Write-Host '1. Open https://azure.microsoft.com/free/ and sign in with your Microsoft account.'
    Write-Host '2. Create a free trial account if eligible.'
    Write-Host '3. Use `az login` again and select the new free-tier subscription.'
    return $status
}

function Setup-AzureFreeTierEnvironment {
    param(
        [string]$ResourceGroupName = 'free-tier-rg',
        [string]$Location = 'eastus'
    )

    Ensure-AzureCLI
    Connect-AzureAccount
    Select-AzureSubscription

    $currentAccount = Get-AzureLoggedInAccount
    if (-not $currentAccount -or -not $currentAccount.id) {
        throw 'Unable to determine the current Azure subscription. Please select a valid subscription with Select-AzureSubscription or supply a subscription ID.'
    }

    Write-Host "Using subscription $($currentAccount.name) ($($currentAccount.id)) in tenant $($currentAccount.tenantId)."

    Write-Host "Creating resource group '$ResourceGroupName' in location '$Location'..."
    Invoke-AzureCli -Arguments @('group', 'create', '--name', $ResourceGroupName, '--location', $Location, '-o', 'none') | Out-Null

    Write-Host 'Creating a free-tier App Service plan (F1)...'
    Invoke-AzureCli -Arguments @('appservice', 'plan', 'create', '--name', 'FreeTierPlan', '--resource-group', $ResourceGroupName, '--sku', 'F1', '--location', $Location, '-o', 'none') | Out-Null

    Write-Host 'Creating a storage account with standard free-compatible settings...'
    $storageName = 'free' + (Get-Random -Minimum 1000 -Maximum 9999)
    Invoke-AzureCli -Arguments @('storage', 'account', 'create', '--name', $storageName, '--resource-group', $ResourceGroupName, '--location', $Location, '--sku', 'Standard_LRS', '--kind', 'StorageV2', '-o', 'none') | Out-Null

    Write-Host 'Free-tier environment setup complete.'
    return [PSCustomObject]@{
        ResourceGroupName = $ResourceGroupName
        Location = $Location
        AppServicePlan = 'FreeTierPlan'
        StorageAccount = $storageName
    }
}

function New-AzureCliClient {
    Ensure-AzureCLI
    return [PSCustomObject]@{
        Connect = { Connect-AzureAccount }
        IsAuthenticated = { [bool](Get-AzureLoggedInAccount) }
        GetLoggedInAccount = { Get-AzureLoggedInAccount }
        GetSubscriptions = { Get-AzureSubscriptions }
        GetSubscriptionData = { param($id) Get-AzureSubscriptionData -SubscriptionId $id }
        GetSubscriptionDetails = { param($id) Get-AzureSubscriptionDetails -SubscriptionId $id }
        GetTenants = { Get-AzureTenants }
        GetFreeTierStatus = { param($id) Get-AzureFreeTierStatus -SubscriptionId $id }
        SetFreeTier = { param($id) Set-AzureAccountFreeTier -SubscriptionId $id }
        SetupEnvironment = { param($rg,$loc) Setup-AzureFreeTierEnvironment -ResourceGroupName $rg -Location $loc }
    }
}

Write-Host 'AzureCLI helper loaded. Use `New-AzureCliClient` to create a client object.'
