<#
This script is used for Azure Security center onboarding.
Written by AirGate Technology Inc.
#>


##import the library to use to read from excel
Install-Module -name psexcel
import-module psexcel


#supply file path and sheet name
$path = ".\Dataset.xlsx"
$sheetName = "Sheet1"
$dataset = new-object System.Collections.ArrayList
#Get the data from workbook
try{
    foreach ($i in (Import-XLSX -Path $path -Sheet $sheetName -RowStart 1)){
        $dataset.add($i) | out-null #I don't want to see the output
    }
    #$dataset| Get-Member |Where-Object {$_.MemberType -eq "NoteProperty"}| Select -ExpandProperty  Name
}
catch{
        Write-Error -Message "Sheetname: $($sheetName) not found"
        return
}

#if data exists, proceed with onboarding
if($dataset)
{
    Connect-AzAccount
    #define parameters to onboard
    [array] $solutionstandard= "SecurityCenterFree", "Security", "SQLAdvancedThreatProtection", "SQLVulnerabilityAssessment"
    [array] $solutionfree= "SecurityCenterFree"

    foreach($data in $dataset)
    {
        $subid = (Set-AzContext $data.SubscriptionId).Subscription.Id
        $scope="/subscriptions/" + $subid
        #***** CONFIGURE WORKSPACE*********#
        #Check if a workspace exist
        $workspaceId=(Get-AzOperationalInsightsWorkspace -Name $data.WorkspaceName -ResourceGroupName $data.ResourceGroup -ErrorAction SilentlyContinue).ResourceId
        if(!$workspaceId)
        {
            #if no workspace, proceed with creating a workspace to use
            Write-Host "Initiating workspace creation" -ForegroundColor Cyan

            #generate tags for the workspace
            $tags= @{
                    "lll:deployment:environment" = $data."lll:deployment:environment"
                    "lll:deployment:deployed-by" = $data."lll:deployment:deployed-by"
                    "lll:business:project-name" = $data."lll:business:project-name"
                    "lll:business:department" = $data."lll:business:department"
                    "lll:business:project-code"  = $data."lll:business:project-code"
                    "lll:business:cost-center" = $data."lll:business:cost-center"
                        }          
            #CREATE NEW RESOURCE GROUP
            New-AzResourceGroup -Name $data.ResourceGroup  -Location $data.Location -Tag $tags
            Write-Host "$($data.ResourceGroup) Resource group created"  -ForegroundColor Green
                

            #CREATE NEW WORKSPACE
            $workspaceId = (New-AzOperationalInsightsWorkspace  -Name $data.WorkspaceName -ResourceGroupName $data.ResourceGroup -Location $data.Location -Sku $data.'Workspace SKU' -Tag $tags).ResourceId
            Write-Host "$($data.WorkspaceName) created" -ForegroundColor Green
        }
        if($workspaceId)
        {
            # get the specified solutions 
            if($data.'ASC PricingTier'.ToLower() -eq "free")
            {
                $solutions = $solutionfree
                Write-Host "Free ASC selected" -ForegroundColor Cyan
            }
            if($data.'ASC PricingTier'.ToLower() -eq "standard")
            {
                $solutions = $solutionstandard
                Write-Host "Standard ASC selected" -ForegroundColor Cyan
            }
            if($solutions)
            {
                # ADD SOLUTION PACKS TO WORKSPACE
                Write-Host "Adding security center solutions" -ForegroundColor Cyan
                foreach($solution in $solutions)
                {           
                    Set-AzOperationalInsightsIntelligencePack -ResourceGroupName $data.ResourceGroup `
                                                    -WorkspaceName $data.WorkspaceName `
                                                    -IntelligencePackName $solution -Enabled $true
                    sleep(5)
                }
            }    
            #SET ASC WORKSPACE TO DEFINED WORKSPACE                       
            Set-AzSecurityWorkspaceSetting -Name "default" -Scope $scope  -WorkspaceId $workspaceId
        }
        else
        {           
            Write-Host  "Unable to set workspace - No valid workspace Id" -ForegroundColor Red
        }
     
        #SLEEP FOR PREVIOUS OPERATIONS TO PROPAGATE
        sleep(5)

        #SET AUTOPROVISIONING, IF NOT ENABLED
        if((Get-AzSecurityAutoProvisioningSetting).AutoProvision -eq "Off")
        {
            Set-AzSecurityAutoProvisioningSetting -Name "default" -EnableAutoProvision #-WhatIf
            Write-Host "AutoProvision Enabled" -ForegroundColor Green
        }
        else
        {
            Write-Host "AutoProvision Already Enabled" -ForegroundColor White
        }


        if($workspaceId)
        {
            Write-Host "Setting ASC Workspace" -ForegroundColor Cyan                                         
            Set-AzSecurityWorkspaceSetting -Name "default" -Scope $scope  -WorkspaceId $workspaceId
        }
        else
        {
            Write-Host  "Unable to set workspace" -ForegroundColor Red
        }
        #*****Configure ASC pricing*********#     
        #GET ASC PRICING
        $pricingtiers= Get-AzSecurityPricing
        if($pricingtiers.PricingTier -contains "Free")
        {
            # UPGRADE ASC TO STANDARD
            Write-Host "Upgrading pricing tier to standard" -ForegroundColor Cyan
            foreach($pricingtier in $pricingtiers)
            {
                if($pricingtier.PricingTier -ne "Standard")
                {
                    Set-AzSecurityPricing -Name $pricingtier.Name -PricingTier "Standard" 
                }
            }
            Write-Host "Upgrade Completed" -ForegroundColor Green
        }
  
        #*****Configure Notification*********# 
        if(!(Get-AzSecurityContact) -and $data.Email)
        {
            #SET NOTIFICATION CONTACT
            Write-Host "Adding notification contact" -ForegroundColor Cyan
            Set-AzSecurityContact -Name "default1" -Email $data.Email -NotifyOnAlert # -AlertAdmin #confirm
        }

    
    }

    Write-Host "Task Completed" -ForegroundColor Green
}
else{
    Write-Host "No Dataset" -ForegroundColor Red
}
