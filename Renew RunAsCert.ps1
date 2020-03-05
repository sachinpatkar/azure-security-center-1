﻿<#
.SYNOPSIS
    This script will grant the required permission to Azure Automation Run As Account AAD Application to 
    renew the ceritifcate itself and create a schedule for monthly/weekly renewal.
    
.MODULES REQUIRED (PREREQUISITES)
     This script uses the below modules
         Az.Profile
         Az.Automation
         Az.Resources
         AzureAD
     Please use the below command to install the modules (if the modules are not in the local computer)
         Install-Module -Name Az.Profile
         Install-Module -Name Az.Automation
         Install-Module -Name Az.Resources
         Install-Module -Name AzureAD
.DESCRIPTION
    This script will grant the required permission to Azure Automation Run As Account AAD Application to renew the ceritifcate itself.
    A. You need to be an Global Administrator / Company Administrator in Azure AD to be able to execute this script.
        Related Doc : https://docs.microsoft.com/en-us/azure/active-directory/users-groups-roles/directory-assign-admin-roles#available-roles
    B. This Power Shell script is doing the following operations
         1) Get the Run As Account AAD ApplicationId from automation connection asset "AzureRunAsConnection".
         2) Grant Owner permission to RunAsAccount AAD Service Principal for RunAsAccount AAD Application.
         3) Assign the "Application.ReadWrite.OwnedBy" App Role to the RunAsAccount AAD Service Principal.
         4) Import Update Azure Modules runbook from github open source and Start Update Azure Modules
            (Related link : https://raw.githubusercontent.com/Microsoft/AzureAutomation-Account-Modules-Update/master/Update-AutomationAzureModulesForAccount.ps1)
         5) Import UpdateAutomationRunAsCredential runbook
            (Related link : https://raw.githubusercontent.com/azureautomation/runbooks/master/Utility/ARM/Update-AutomationRunAsCredential.ps1 )
         6) Create a weekly or monthly schedule for UpdateAutomationRunAsCredential runbook
         7) Start the UpdateAutomationRunAsCredential onetime
   
.USAGE
    .\GrantPermissionToRunAsAccountAADApplication-ToRenewCertificateItself-CreateSchedule.ps1 -ResourceGroup <ResourceGroupName> `
            -AutomationAccountName <NameofAutomationAccount> `
            -SubscriptionId <SubscriptionId> 
.NOTES
    AUTHOR: AirGate Automation Team
    LASTEDIT: Jan 28th, 2020
#>
Param (
    [Parameter(Mandatory = $true)]
    [String] $ResourceGroup,

    [Parameter(Mandatory = $true)]
    [String] $AutomationAccountName,

    [Parameter(Mandatory = $true)]
    [String] $SubscriptionId,

    [Parameter(Mandatory = $true)]
    [ValidateSet("Monthly", "Weekly")]
    [string]$ScheduleRenewalInterval,

    [Parameter(Mandatory = $true)]
    [ValidateSet("AzureCloud", "AzureUSGovernment", "AzureChinaCloud")]
    [string]$EnvironmentName
)


$message = "This script will 1) Grant Owner permission to Automation RunAsAccount AAD Service Principal for RunAsAccount AAD Application."
$message = $message + "2) Assign the 'Application.ReadWrite.OwnedBy' App Role to the RunAsAccount AAD Service Principal."
$message = $message + "Do you want To Proceed? (Y/N):"
$confirmation = Read-Host $message 
if ($confirmation -ieq 'N') {
  EXIT(1)
}

#Import-Module Az.Profile
#Import-Module Az.Automation
#Import-Module Az.Resources
#Import-Module AzureAD

Connect-AzAccount
$subscription = Select-AzSubscription -SubscriptionId $SubscriptionId

$currentAzureContext = Get-AzContext
$tenantId = $currentAzureContext.Tenant.Id
$accountId = $currentAzureContext.Account.Id
Connect-AzureAD -TenantId $tenantId -AccountId $accountId

$automationAccount = Get-AzAutomationAccount -ResourceGroupName $ResourceGroup -Name $AutomationAccountName

# Step 1: Get the Run As Account AAD ApplicationId from automation connectionAsset "AzureRunAsConnection"
$connectionAssetName = "AzureRunAsConnection"
$runasAccountConnection = Get-AzAutomationConnection -Name $connectionAssetName `
                          -ResourceGroupName $ResourceGroup  -AutomationAccountName $AutomationAccountName
[GUID]$runasAccountAADAplicationId=$runasAccountConnection.FieldDefinitionValues['ApplicationId']

$runasAccountAADAplication = Get-AzADApplication -ApplicationId $runasAccountAADAplicationId
$runasAccountAADservicePrincipal = Get-AzureADServicePrincipal -Filter "AppId eq '$runasAccountAADAplicationId'"

# Step 2: Grant Owner permission to RunAsAccount AAD Service Principal for RunAsAccount AAD Application
Add-AzureADApplicationOwner -ObjectId $runasAccountAADAplication.ObjectId `
 -RefObjectId $runasAccountAADservicePrincipal.ObjectId -ErrorAction SilentlyContinue

# Get the Service Principal for the Azure AD Graph
# App ID of AAD Graph:
$AADGraphAppId = "00000002-0000-0000-c000-000000000000"
$graphServicePrincipal = Get-AzureADServicePrincipal -Filter "appId eq '$AADGraphAppId'"
# On the Graph Service Principal, find the App Role "Application.ReadWrite.OwnedBy" 
# that has the permission to update the Application
$permissionName = "Application.ReadWrite.OwnedBy"
$appRole = $graphServicePrincipal.appRoles | Where-Object {$_.Value -eq $permissionName -and $_.AllowedMemberTypes -contains "Application"}
# Step 3: Assign the "Application.ReadWrite.OwnedBy" App Role to the RunAsAccount AAD Service Principal.
$appRoleAssignment = New-AzureAdServiceappRoleAssignment `
  -ObjectId $runasAccountAADservicePrincipal.ObjectId `
  -PrincipalId $runasAccountAADservicePrincipal.ObjectId `
  -ResourceId $graphServicePrincipal.ObjectId -Id $appRole.Id 

# Step 4: Import Update Azure Modules runbook from github open source and Start Update Azure Modules
$updateAzureModulesForAccountRunbookName = "Update-AutomationAzureModulesForAccount"
$updateAzureModulesForAccountRunbookPath = Join-Path $env:TEMP ($updateAzureModulesForAccountRunbookName+".ps1")
wget -Uri https://raw.githubusercontent.com/Microsoft/AzureAutomation-Account-Modules-Update/master/Update-AutomationAzureModulesForAccount.ps1 `
     -OutFile $updateAzureModulesForAccountRunbookPath
$importUpdateAzureModulesForAccountRunbook = Import-AzAutomationRunbook -ResourceGroupName $ResourceGroup `
  -AutomationAccountName $AutomationAccountName `
  -Path $updateAzureModulesForAccountRunbookPath -Type PowerShell
$publishUpdateAzureModulesForAccountRunbook = Publish-AzAutomationRunbook `
   -Name $updateAzureModulesForAccountRunbookName `
   -ResourceGroupName $ResourceGroup `
   -AutomationAccountName $AutomationAccountName
$runbookParameters = @{"AUTOMATIONACCOUNTNAME"=$AutomationAccountName;"RESOURCEGROUPNAME"=$ResourceGroup; "AZUREENVIRONMENT"=$EnvironmentName}
$updateModulesJob = Start-AzAutomationRunbook -Name $updateAzureModulesForAccountRunbookName `
  -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccountName -Parameters $runbookParameters

# Step 5: Import UpdateAutomationRunAsCredential runbook
$UpdateAutomationRunAsCredentialRunbookName = "Update-AutomationRunAsCredential"
$UpdateAutomationRunAsCredentialRunbookPath = Join-Path $env:TEMP ($UpdateAutomationRunAsCredentialRunbookName+".ps1")
wget -Uri https://raw.githubusercontent.com/azureautomation/runbooks/master/Utility/ARM/Update-AutomationRunAsCredential.ps1 `
    -OutFile $UpdateAutomationRunAsCredentialRunbookPath
$ImportUpdateAutomationRunAsCredentialRunbook = Import-AzAutomationRunbook -ResourceGroupName $ResourceGroup `
    -AutomationAccountName $AutomationAccountName `
    -Path $UpdateAutomationRunAsCredentialRunbookPath -Type PowerShell
$PublishUpdateAutomationRunAsCredentialRunbook = Publish-AzAutomationRunbook `
    -Name $UpdateAutomationRunAsCredentialRunbookName `
    -ResourceGroupName $ResourceGroup `
    -AutomationAccountName $AutomationAccountName

# Step 6: Create a weekly or monthly schedule for UpdateAutomationRunAsCredential runbook
$scheduleName="UpdateAutomationRunAsCredentialSchedule"
$todayDate = get-date -Hour 0 -Minute 00 -Second 00
$startDate = $todayDate.AddDays(1)
#Create a Schedule to run $UpdateAutomationRunAsCredentialRunbookName monthly
if ($ScheduleRenewalInterval -eq "Monthly") 
{
  $scheduleName = $scheduleName + $ScheduleRenewalInterval
  $schedule = New-AzAutomationSchedule –AutomationAccountName $AutomationAccountName `
               –Name $scheduleName  -ResourceGroupName $ResourceGroup  `
               -StartTime $startDate -MonthInterval 1 `
               -DaysOfMonth One
} 
elseif ($ScheduleRenewalInterval -eq "Weekly") 
{
  $scheduleName = $scheduleName + $ScheduleRenewalInterval  
  $schedule = New-AzAutomationSchedule –AutomationAccountName $AutomationAccountName `
               –Name $scheduleName  -ResourceGroupName $ResourceGroup `
               -StartTime $startDate -DaysOfWeek Sunday `
               -WeekInterval 1  
}
$registerdScuedule = Register-AzAutomationScheduledRunbook –AutomationAccountName $AutomationAccountName `
 -ResourceGroupName $ResourceGroup -ScheduleName $scheduleName `
 -RunbookName $UpdateAutomationRunAsCredentialRunbookName

# Step 7: Start the UpdateAutomationRunAsCredential onetime
do {
   $updateModulesJob = Get-AzAutomationJob -Id $updateModulesJob.JobId -ResourceGroupName $ResourceGroup `
                         -AutomationAccountName $AutomationAccountName
   Write-Output ("Updating Azure Modules for automation account..." + "Job Status is " + $updateModulesJob.Status)
   Sleep 30
} while ($updateModulesJob.Status -ne "Completed" -and $updateModulesJob.Status -ne "Failed" -and $updateModulesJob.Status -ne "Suspended")

if ($updateModulesJob.Status -eq "Completed")
{
  Write-Output ("Updated Azure Modules for " + $AutomationAccountName)
  $updateAutomationRunAsCredentialJob = Start-AzAutomationRunbook `
    -Name $UpdateAutomationRunAsCredentialRunbookName `
    -ResourceGroupName $ResourceGroup -AutomationAccountName $AutomationAccountName
  $message = "UpdateAutomationRunAsCredential job started for automation account " + $AutomationAccountName 
  $message = $message + ".Please check AzurePortal for job status of jobid " + $updateAutomationRunAsCredentialJob.JobId.ToString()
  Write-Host -ForegroundColor green $message
} 
else
{
   $message = "Updated Azure Modules job completed with status " + $updateModulesJob.Status + ".Please debug the issue."
   Write-Host -ForegroundColor red $message
}