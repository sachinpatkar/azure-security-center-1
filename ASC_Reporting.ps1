param(
    [Parameter(Mandatory = $true, 
    HelpMessage= "Storage account name")]
    [string]$StorageAccountName,
    [Parameter(Mandatory = $true, 
    HelpMessage= "Storage account Resource group")]
    [string]$StorageResourceGroup,
    [Parameter(Mandatory = $true, 
    HelpMessage= "Subscription ID of the Storage account to save the file")]
    [string]$SubIdStorage ,
    [Parameter(Mandatory = $true, 
    HelpMessage= "Storage account container name")]
    [string]$ContainerName ,
    [Parameter(Mandatory = $true, 
    HelpMessage= "Keyvault name")]
    [string]$VaultName,
    [Parameter(Mandatory = $true, 
    HelpMessage= "Recipient email addresses")]
    [string] $EmailTo
    )

$connectionName = "AzureRunAsConnection"

try 
{
    # Get the connection "AzureRunAsConnection "
    $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName 
    "Logging in to Azure..."
     Add-AzAccount -ServicePrincipal -TenantId $servicePrincipalConnection.TenantId `
    -ApplicationId $servicePrincipalConnection.ApplicationId `
    -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 
}
catch 
{
    if (!$servicePrincipalConnection) 
    {
        $ErrorMessage = "Connection $connectionName not found."
        throw $ErrorMessage
    }
    else 
    {
        Write-Error -Message $_.Exception
        throw $_.Exception
    }
}


# get all subscription in tenant
$subIds=(Get-AzSubscription).Id

# create an empty daset to append
$dataset = @()
$sentdata = ""
foreach($subId in $subIds){
    # Set the subcription context
    $sub= Set-AzContext $subId

    #Get autoprovisioning state
    $Autoprovisioning=(Get-AzSecurityAutoProvisioningSetting).AutoProvision
    
    #Get ASC state
    $acs = Get-AzSecurityPricing | Select-Object Name, PricingTier
    
    #Get ACS workspace state
    $workspace=(Get-AzSecurityWorkspaceSetting).WorkspaceId
    
    #Get workspace name
    if($workspace){
    $workspace=$workspace.split("/")[-1]
    }
    else{
    $workspace=$null
    }

    #combine all ASC item list
    $AllAscPricing = ""
    foreach($item in $acs){
        $acspricing = $item.Name + ": " + $item.PricingTier
        if($AllAscPricing){
        $AllAscPricing =$AllAscPricing + "; " +  $acspricing
        }
        else{
        $AllAscPricing =  $acspricing
        }
    }

    #add the information gathered into the object
    $Sub1 = New-Object System.Object
    $Sub1 | Add-Member -type NoteProperty -name SubscriptionName -Value $sub.Subscription.Name
    $Sub1 | Add-Member -type NoteProperty -name SubscriptionId -Value $sub.Subscription.Id
    $Sub1 | Add-Member -type NoteProperty -name Autoprovisioning -Value $Autoprovisioning
    $Sub1 | Add-Member -type NoteProperty -name workspace -Value $workspace
    $Sub1 | Add-Member -type NoteProperty -name AscPricingTier -Value $AllAscPricing 
    $dataset+= $Sub1

    #create an email body with the information retrieved
    $sentdata =$sentdata+  "SubscriptionName: " + $sub.Subscription.Name + 
    "<br /> SubscriptionId: " + $sub.Subscription.Id + 
    "<br /> Autoprovisioning: " +$Autoprovisioning + 
    "<br /> workspace: " + $workspace + 
    "<br /> AscPricingTier: " +$AllAscPricing +"<br /><br />"
}

#get the file file path
$CurrentMonth = (Get-Date -UFormat %B) 
$outfileName = $CurrentMonth + "_ASC_Report.xlsx"


$dataset| Select-Object * | Export-Excel $outfileName

# if file exist, initiate azure storage uploac
if (Test-Path -path $outfileName){

    # set context to storage location
    Set-AzContext $SubIdStorage 

    #Get key to storage account
    $acctKey = (Get-AzStorageAccountKey -Name $StorageAccountName -ResourceGroupName $StorageResourceGroup).Value[0]

    #Creates an Azure Storage context. 
    $storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $acctKey

    $blobexist=Get-AzStorageContainer -Name $ContainerName -Context $storageContext -ErrorAction SilentlyContinue

    if(!$blobexist)
    {
        New-AzStorageContainer -Name $ContainerName -Context $storageContext
    }
    #Copy the file to the storage account
    Set-AzStorageBlobContent -File $outfileName -Container $ContainerName -BlobType "Block" -Context $storageContext -Verbose -Force

}

##**********send Email Initiated ***************##
# get username and password from vault
if($VaultName -and $EmailTo){
    $Username = Get-AzKeyVaultSecret -VaultName $VaultName -Name 'username'
    $Username = $Username.SecretValueText

    $Password = Get-AzKeyVaultSecret -VaultName $VaultName -Name 'password'
    $Password = $Password.SecretValueText

    #prepare and send the list of policy violator(s) to the admin
    if($Username -and $Password){
        $Password = ConvertTo-SecureString $Password -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential $Username, $Password
        $SMTPServer = "smtp.sendgrid.net"
        $EmailFrom = "ascreport@ascreporter.ca"
        $Subject = "$CurrentMonth ACS report"
        $Body = "ASC report for $CurrentMonth is as follows:<br /><br />" + $sentdata +"<br /><br /><br />" +"Regards,"+"<br />ASC Reporter"
        Send-MailMessage -smtpServer $SMTPServer -Credential $credential -Usessl -Port 587 -from $EmailFrom -to $EmailTo -subject $Subject -Body $Body -BodyAsHtml -Attachments $outfileName
        Write-Output "Email sent succesfully." 
    }  
}

#delete file locally
if(!(Test-Path -path $outfileName))
{
    Remove-Item –path $outfileName
    Test-Path -path $outfileName
}
