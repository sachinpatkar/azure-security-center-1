Param (
    [Parameter(Mandatory = $true,
    HelpMessage = "Supply Region, ex. Canada Central")]
    [String] $region,

    [Parameter(Mandatory = $true,
    HelpMessage = "Supply already existing Subscription ID")]
    [String] $SubscriptionID,

    [Parameter(Mandatory = $true,
    HelpMessage = "Supply already existing Tenant ID")]
    [String] $TenantID,

    [Parameter(Mandatory = $true,
    HelpMessage = "Supply already existing Resource GroupName")]
    [String] $ResourceGroupName,

    [Parameter(Mandatory = $true,
    HelpMessage = "Supply Vault Name to be created")]
    [String] $VaultName,

    [Parameter(Mandatory = $true,
    HelpMessage = "Supply Storage Account Name to be created")]
    [String] $StorageAccountName ,

    [Parameter(Mandatory = $true,
    HelpMessage = "Supply container name in Storage Account to be created")]
    [String] $ContainerName,
    
    [Parameter(Mandatory = $true,
    HelpMessage = "Supply mailing distribution list to send reports, separated by comma")]
    [string] $EmailTo,
    
    [Parameter(Mandatory = $true,
    HelpMessage = "Supply already existing Automation Account Name")]
    [String] $AutomationAccountName,

    [Parameter(Mandatory = $true,
    HelpMessage = "Supply already existing Application Display Name")]
    [String] $ApplicationDisplayName,

    [Parameter(Mandatory = $true,
    HelpMessage = "Supply Self-Signed Cert Plain Password")]
    [Security.SecureString] $SelfSignedCertPlainPassword,

    [Parameter(Mandatory = $true,
    HelpMessage = "Supply SendGrid Username from SendGrid Portal")]
    [String] $SendGridUsername,

    [Parameter(Mandatory = $true,
    HelpMessage = "Supply SendGrid password from SendGrid Portal")]
    [Security.SecureString] $SendGridPassword,

    [Parameter(Mandatory = $true,
    HelpMessage = "Supply Runbook Name to be created")]
    [String] $runbookName
    
)


## Import some needed modules
## Install-Module -name psexcel
Import-module psexcel
Import-Module Az.Automation
Enable-AzureRmAlias

Connect-AzAccount
$Error[0]= $null #reset errors
Set-AzContext -SubscriptionId $SubscriptionID -TenantId $TenantID -ErrorAction Stop

## get tags from dataset

## supply file path and sheet name
## Get the data from workbook

write-host "Getting tags from Dataset.xlxs to tag Resources" -ForegroundColor Yellow
$path = ".\Dataset.xlsx"
$sheetName = "Sheet2"
$dataset2 = new-object System.Collections.ArrayList

try{
    foreach ($i in (Import-XLSX -Path $path -Sheet $sheetName -RowStart 1)){
        $dataset2.add($i) | out-null #I don't want to see the output
    }
}
catch{
        Write-Error -Message "Sheetname: $($sheetName) not found"
        return
}

#Create Automation account and RunAs Account
Write-host "Creating required Resource Group.." -ForegroundColor Cyan

$data =  $dataset2| Select-Object * |where {$_.ResourceType -eq "resourcegroup"} 
$tags= @{
            "lll:deployment:environment" = $data."lll:deployment:environment"
            "lll:deployment:deployed-by" = $data."lll:deployment:deployed-by"
            "lll:business:project-name" = $data."lll:business:project-name"
            "lll:business:department" = $data."lll:business:department"
            "lll:business:project-code"  = $data."lll:business:project-code"
            "lll:business:cost-center" = $data."lll:business:cost-center"
        }
New-AzResourceGroup -Name $ResourceGroupName -Location $region -Tag $tags

Write-host "Checking if Automation Account exists.." -ForegroundColor Yellow
$CheckAA = Get-AzAutomationAccount -Name $AutomationAccountName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue

if ($CheckAA)
{
    Write-host "Automation Account provided Already exists" -ForegroundColor Green   
}
else
{
    Write-host "Creating Automation Account.." -ForegroundColor Cyan

    $data =  $dataset2| Select-Object * |where {$_.ResourceType -eq "automationaccount"} 
    $tags= @{
            "lll:deployment:environment" = $data."lll:deployment:environment"
            "lll:deployment:deployed-by" = $data."lll:deployment:deployed-by"
            "lll:business:project-name" = $data."lll:business:project-name"
            "lll:business:department" = $data."lll:business:department"
            "lll:business:project-code"  = $data."lll:business:project-code"
            "lll:business:cost-center" = $data."lll:business:cost-center"
        }
    $Error[0]= $null
    New-AzAutomationAccount -ResourceGroupName $ResourceGroupName -Name $AutomationAccountName -Location $region -Tags $tags
    
    if($Error[0].Exception)
    {
        Write-host "Error while creating the Automation Account" -ForegroundColor red
        return
    }
    else
    {
        write-host "Automation Account created successfully" -ForegroundColor Green
    }
}

## Checking if Automation Run As Account is assocciated to this automation account or not
$CheckRunAsAccount = (Get-AzAutomationConnection -AutomationAccountName  $AutomationAccountName -ResourceGroupName $ResourceGroupName).Name

if(!$CheckRunAsAccount -Contains "AzureRunAsConnection"){
    Write-host "Creating Run As Account and granting Contributor Access to it.." -ForegroundColor Cyan
    .\New-RunAsAccount.ps1 -ResourceGroup $ResourceGroupName -AutomationAccountName $AutomationAccountName -SubscriptionId $SubscriptionID -ApplicationDisplayName $ApplicationDisplayName -SelfSignedCertPlainPassword $SelfSignedCertPlainPassword -CreateClassicRunAsAccount $false
}
else
{
    Write-host "Automation Account 'Run As Account' already exists" -ForegroundColor Green  
}

## Assign Contributor role to the same RunAs Account on all subscriptions in scope
## Input subscriptions ID from a csv file

## Supply file path and sheet name
$path = ".\Dataset.xlsx"
$sheetName = "Sheet1"
$dataset = new-object System.Collections.ArrayList

#Get the data from workbook
try{
    foreach ($i in (Import-XLSX -Path $path -Sheet $sheetName -RowStart 1))
        {
         $dataset.add($i) | out-null 
        }
    }
catch
{
    Write-Error -Message "Sheetname: $($sheetName) not found"
    return
}

if($dataset)
{
    Write-host "Assigning Contributor to Run As Account in all other subscriptions in scope.." -ForegroundColor Cyan
    foreach($data in $dataset)
    {
        $subid = $data.SubscriptionId
        Set-AzContext -Subscription $subid -TenantId $TenantID
        $Application = Get-AzADApplication -DisplayName $ApplicationDisplayName
        try
        {
            $NewRole = New-AzureRMRoleAssignment -RoleDefinitionName Contributor -ServicePrincipalName $Application.ApplicationId -ErrorAction SilentlyContinue
        }
        catch
        {
            Write-host "Can't Assign Contributor on all provided subscriptions" -ForegroundColor red
            return
        }
    }
}

# Check if keyvault already exist
$CheckKV = Get-AzKeyVault -VaultName $VaultName  -ErrorAction SilentlyContinue

if ($CheckKV)
{
   Write-host "Key Vault provided already exists, it will be reused.." -ForegroundColor Green
   $resourceId = $CheckKV.ResourceId
}
else
{
    Write-host "Creating Key Vault.." -ForegroundColor Cyan
    #get tags
    $data =  $dataset2| Select-Object * |where {$_.ResourceType -eq "keyvault"} 
    $tags= @{
            "lll:deployment:environment" = $data."lll:deployment:environment"
            "lll:deployment:deployed-by" = $data."lll:deployment:deployed-by"
            "lll:business:project-name" = $data."lll:business:project-name"
            "lll:business:department" = $data."lll:business:department"
            "lll:business:project-code"  = $data."lll:business:project-code"
            "lll:business:cost-center" = $data."lll:business:cost-center"
        }
    $Error[0]= $null
    $newKeyVault = New-AzKeyVault -VaultName $VaultName -ResourceGroupName $ResourceGroupName -Location $region -Tag $tags
    $resourceId = $newKeyVault.ResourceId
    
    if($Error[0].Exception)
    {
        Write-host "Error while creating the Key Vault" -ForegroundColor red
        return
    }
    else
    {
        write-host "Key Vault created successfully" -ForegroundColor Green
    }
}


# Convert the SendGrid username and password into a SecureString
Write-host "Saving SendGrid Username and password as secrets in Key Vault.." -ForegroundColor Yellow
$SecretUser = ConvertTo-SecureString -String $SendGridUsername -AsPlainText -Force 
$SecretPass = $SendGridPassword #password is already encrypted by input parameters.
Set-AzKeyVaultSecret -VaultName $VaultName -Name 'username' -SecretValue $SecretUser
Set-AzKeyVaultSecret -VaultName $VaultName -Name 'password' -SecretValue $SecretPass

# Grant access to the KeyVault to the Automation RunAs account.
Write-host "Granting Access to Automation Run As Account to access Key Vault secrets.." -ForegroundColor Cyan
$connection = Get-AzAutomationConnection -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name AzureRunAsConnection
$appID = $connection.FieldDefinitionValues.ApplicationId
Set-AzKeyVaultAccessPolicy -VaultName $VaultName -ServicePrincipalName $appID -PermissionsToSecrets Get, List


#Create Storage Account to Save monthly reports
$CheckSA = Get-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
if ($CheckSA)
{
       Write-host "Storage Account already exists, it will be reused.." -ForegroundColor Green
   
}
else{
    Write-host "Creating Storage Account to save reports in.." -ForegroundColor Cyan
    ## Get tags
    $data =  $dataset2| Select-Object * |where {$_.ResourceType -eq "storageaccount"} 
    $tags= @{
            "lll:deployment:environment" = $data."lll:deployment:environment"
            "lll:deployment:deployed-by" = $data."lll:deployment:deployed-by"
            "lll:business:project-name" = $data."lll:business:project-name"
            "lll:business:department" = $data."lll:business:department"
            "lll:business:project-code"  = $data."lll:business:project-code"
            "lll:business:cost-center" = $data."lll:business:cost-center"
        }

    $Error[0]= $null
    New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Location canadacentral -SkuName Standard_LRS -Kind BlobStorage -AccessTier cool -Tag $tags
    if($Error[0].Exception)
    {
        Write-host "Error while creating the Storage Account" -ForegroundColor red
        return
    }
    else
    {
        write-host "Storage Account created successfully" -ForegroundColor Green
    }
}


## Create, Import and Publish Runbook
Write-host "Importing Reporting script Runbook into Automation Account.." -ForegroundColor Cyan
$scriptPath = ".\ASC_Reporting.ps1"

## Get tags
    $data =  $dataset2| Select-Object * |where {$_.ResourceType -eq "automationaccount"} 
    $tags= @{
            "lll:deployment:environment" = $data."lll:deployment:environment"
            "lll:deployment:deployed-by" = $data."lll:deployment:deployed-by"
            "lll:business:project-name" = $data."lll:business:project-name"
            "lll:business:department" = $data."lll:business:department"
            "lll:business:project-code"  = $data."lll:business:project-code"
            "lll:business:cost-center" = $data."lll:business:cost-center"
        }


Import-AzAutomationRunbook -Name $runbookName -Path $scriptPath -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Type PowerShell -Tags $tags

Write-host "Publishing Runbook.." -ForegroundColor Yellow
Publish-AzureRmAutomationRunbook -AutomationAccountName $AutomationAccountName -Name $runbookName -ResourceGroupName $ResourceGroupName

# Create Schedule
Write-host "Creating Schedule for runbook to run monthly.." -ForegroundColor Cyan
$StartTime = (Get-Date "4:00:00").AddDays(1)
New-AzAutomationSchedule -AutomationAccountName $AutomationAccountName -Name "ASC_Monthly_Reporting" -StartTime $StartTime -DaysOfMonth @("One") -ResourceGroupName $ResourceGroupName -MonthInterval 1 

# Link Runbook to Schedule and sending parameters
Write-host "Linking Schedule to Runbook.." -ForegroundColor Yellow

# Prepare Parameters for Runbook Scheduler
    $Parameters = @{"StorageAccountName" = $StorageAccountName
    "StorageResourceGroup" = $ResourceGroupName
    "SubIdStorage" = $SubscriptionID
    "ContainerName" = $ContainerName
    "VaultName" = $VaultName
    "EmailTo" = $EmailTo}

$Error[0]= $null
Register-AzAutomationScheduledRunbook –AutomationAccountName $AutomationAccountName –Name $runbookName –ScheduleName "ASC_Monthly_Reporting" -ResourceGroupName $ResourceGroupName -Parameters $Parameters 
    
if($Error[0].Exception)
{
    Write-host "Error while Registring the Runbook with Scheduler" -ForegroundColor red
    return
}
else
{
    write-host "Runbook created, Published and registered with Scheduler" -ForegroundColor Green
}

#Importing PowerShell modules for the use of the automation account
Write-host "Importing some needed modules to Automation Account.." -ForegroundColor Cyan
Write-host "Importing Az.Profile.." -ForegroundColor Yellow
$moduleName = "Az.Profile"
$moduleVersion =  "0.7.0"
New-AzAutomationModule -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $moduleName -ContentLinkUri "https://www.powershellgallery.com/api/v2/package/$moduleName/$moduleVersion"
sleep -Seconds 240

Write-host "Importing Az.Accounts.." -ForegroundColor Yellow
$moduleName = "Az.Accounts"
$moduleVersion =  "1.7.0"
New-AzAutomationModule -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $moduleName -ContentLinkUri "https://www.powershellgallery.com/api/v2/package/$moduleName/$moduleVersion"
sleep -Seconds 240

Write-host "Importing Az.Security.." -ForegroundColor Yellow
$moduleName = "Az.Security"
$moduleVersion =  "0.7.7"
New-AzAutomationModule -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $moduleName -ContentLinkUri "https://www.powershellgallery.com/api/v2/package/$moduleName/$moduleVersion"

Write-host "Importing Az.Storage.." -ForegroundColor Yellow
$moduleName = "Az.Storage"
$moduleVersion =  "1.11.0"
New-AzAutomationModule -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $moduleName -ContentLinkUri "https://www.powershellgallery.com/api/v2/package/$moduleName/$moduleVersion"

Write-host "Importing Az.KeyVault.." -ForegroundColor Yellow
$moduleName = "Az.KeyVault"
$moduleVersion =  "1.4.0"
New-AzAutomationModule -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $moduleName -ContentLinkUri "https://www.powershellgallery.com/api/v2/package/$moduleName/$moduleVersion"

Write-host "Importing ImportExcel.." -ForegroundColor Yellow
$moduleName = "ImportExcel"
$moduleVersion =  "7.0.1"
New-AzAutomationModule -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName -Name $moduleName -ContentLinkUri "https://www.powershellgallery.com/api/v2/package/$moduleName/$moduleVersion"
sleep -Seconds 240

Write-host "Script Completed" -ForegroundColor Green
