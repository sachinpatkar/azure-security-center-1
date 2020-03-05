# Azure ASC Automation Scripts

### PowerShell Versions
5.1

### Provided By
[AirGate Techonologies Inc](https://airgate.ca)

![AirGate Techonologies Inc](https://static.wixstatic.com/media/ad3e20_a8d5373e614c4180a19d90acf8f198b5~mv2.png/v1/fill/w_258,h_75,al_c,q_80,usm_0.66_1.00_0.01/AirGate%20Hi%20Res%20Connect%20to%20the%20Cloud.webp)
### Instructions

Make sure to run PowerShell as an admin_

_Note: in all parameters you enter manually below, make sure to avoid spaces in all resource names.
Storage account should be all small letters and no spaces and between 3 to 24 characters._

**Azure Security Center Onboarding:**

1. Update the Dataset excel sheet with your input subscriptions and details you need to setup in your environment

**Inputs are:**

  - SubscriptionId: subscription IDs you want to upgrade to Standard
  - WorkspaceName: Name of Log Analytics workspace that will save the ASC data
  - sku: SKU of the log analytics workspace (preferred to be per GB)
  - ResourceGroup: Name of resource Group containing the new created workspace
  - Location: Your Azure Region, ex. Canada Central, US West 2, etc.
  - Email: SOC Email for this subscription to receive highly important alerts
  - Workspace ASC Solutions PricingTier: ASC Pricing

2. Run the **ASC\_Onboarding.ps1** script from a PowerShell Console:

  - Open PowerShell (Run as Administrator on the machine)
  - Go the path where you&#39;ve put all your extracted scripts and files using command > CD **path**
  - Run the script by typing **.\ ASC\_Onboarding.ps1**
  - When Prompted to login to Azure after starting the script run, log in with an account which is at least has an **Application Admin role** n Active Directory and an **Owner Role** on all Azure subscriptions in your environment.

**Azure Security Center Reporting:**

1. Run the **&quot;Create SendGrid.PS1&quot;** script by typing **.\Create SendGrid.ps1** using the same users with the permissions mentioned above. You will be prompted to enter the following.

  - [region] ex &quot;Canada Central&quot;
  - [SubscriptionID] Default Subscription that will host the SendGrid Service ex. the **LLL Infra Prod** subscription ID, you can get it from Azure portal > Subscriptions
  - [TenantID] Tenant ID, you can get it from your Azure Active Directory from the portal.
  - [ResourceGroup] ResourceGroup Name that will host the SendGrid specifically
  - You will be prompted to enter your SendGrid Password, after choosing a password, save it so you can need it in the future.
  - accounts\_SendGrid\_acceptMarketingEmails:  Has to be **Yes** or **No**
  - Will take time to commit.

**Note:** Default Name for the SendGrid account is available in the template JSON file &quot; **SendGrid Template.json&quot;** , in the line: _&quot;defaultValue&quot;: &quot;Lululemon\_SendGrid&quot;_. You can edit this file if you want to change the name, or to create additional SendGrid accounts in the future.

2. Go to the Azure Portal to the Default subscription we created SendGrid service at (assuming its **LLL Infra Prod** ) and go to **Send Grid Accounts** -\&gt; you should see the new &quot; **Lululemon SendGrid**&quot; Account, press on it, in Overview section press on &quot; **Manage**&quot; button, a URL will open your SendGrid account in a browser. Press on **Settings** in the left bar then &quot; **Account Details**&quot;. Copy the username as we will use it in the next steps.

3. Make sure you put the **&quot;New-RunAsAccount.ps1&quot;** script in the same path where you are running your &quot;Core Preparation.ps1&quot; code. Same goes for all scripts.

4. Run the &quot; **Core Preparation.ps1**&quot; script using the same users with the permissions mentioned above. You will be prompted to enter the following.

  - [region] ex &quot;Canada Central&quot;
  - [SubscriptionID] Default Subscription that will host the SendGrid Service ex. the **LLL Infra Prod** subscription ID, you can get it from Azure portal \&gt; Subscriptions
  - [TenantID] Tenant ID, you can get it from your Azure Active Directory from the portal.
  - [ResourceGroupName] Resource Group Name that will contain the SendGrid, you use the same resource group name in all upcoming scripts
  - [VaultName] to be created
  - [StorageAccountName] Choose a name for your storage account to be created that will host your monthly reports. **NOTE: Has to be all small letters with no spaces**
  - [AutomationAccountName] Choose a name for the automation account to be created
  - [ApplicationDisplayName] Choose a name for the Application associated with the automation account to be created
  - [SelfSignedCertPlainPassword] You will be prompted to insert a new Run As account certificate password
  - [SendGridUsername] Use the Username you saved from SendGrid portal **After** creation from previous steps mentioned above
  - [SendGridPassword] You will be prompted to insert the **SAME** password you entered in the SendGrid creation step
  - [runbookName] Choose a name for your new reporting runbook

5. For future use: **&quot;Renew RunAsCert.ps1&quot;** script, is used on its own to renew the &quot;Run as Account&quot; certificate, with expires after a year. The &quot;Run as Account&quot; is used to run the runbooks for the monthly reporting script.

  - [ResourceGroup] Use the resource group that contains the automation account which you need to renew the run as certificate for
  - [AutomationAccountName] Use the automation account name you want to renew its run as account
  - [SubscriptionId]
  - [ScheduleRenewalInterval] Use &quot; **Monthly**&quot;
  - [EnvironmentName] Use &quot; **AzureCloud**&quot;
