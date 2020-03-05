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
    [String] $ResourceGroupName

)

Connect-AzAccount
##import some needed modules
Install-Module -name psexcel
Install-Module Az.MarketplaceOrdering
import-module psexcel
Import-Module Az.Automation
Enable-AzureRmAlias

$templatefile = ".\SendGrid Template.JSON" 
Set-AzContext -Subscription $SubscriptionID -TenantId $TenantID



##get tags from dataset for resource group

#supply file path and sheet name
write-host "Getting tags from Dataset.xlxs to tag Resource Group" -ForegroundColor Yellow
$path = ".\Dataset.xlsx"
$sheetName = "Sheet2"
$dataset = new-object System.Collections.ArrayList
#Get the data from workbook
try{
    foreach ($i in (Import-XLSX -Path $path -Sheet $sheetName -RowStart 1)){
        $dataset.add($i) | out-null 
    }
 }
catch{
        Write-Error -Message "Sheetname: $($sheetName) not found"
        return
}

$data =  $dataset| Select-Object * |where {$_.ResourceType -eq "resourcegroup"} 
$tags= @{
            "lll:deployment:environment" = $data."lll:deployment:environment"
            "lll:deployment:deployed-by" = $data."lll:deployment:deployed-by"
            "lll:business:project-name" = $data."lll:business:project-name"
            "lll:business:department" = $data."lll:business:department"
            "lll:business:project-code"  = $data."lll:business:project-code"
            "lll:business:cost-center" = $data."lll:business:cost-center"
        }

write-host "Creating Resource Group for SendGrid" -ForegroundColor Cyan
New-AzResourceGroup -Name $ResourceGroupName -Location $region -Tag $tags

# Accepting Marketplace Terms for SendGrid Creation
Get-AzMarketplaceTerms -Publisher 'SendGrid' -Product 'sendgrid_azure' -Name 'free' | Set-AzMarketplaceTerms -Accept 

#Create SendGrid from JSON template
write-host "Creating SendGrid Resource from ARM template" -ForegroundColor Cyan
write-host "Please supply SendGrid Tags manually:" -ForegroundColor Yellow
New-AzResourceGroupDeployment -Name SendGridTemplate -ResourceGroupName $ResourceGroupName -TemplateFile $templatefile
$Error[0]= $null
if($Error[0].Exception)
{
    Write-host "Error while creating the SendGrid resource" -ForegroundColor red
    return
}
else
{
    write-host "SendGrid resource created successfully" -ForegroundColor Green
}
