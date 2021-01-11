<#
.History
   11/01/2021 - 1.0 - Initial release - David Alzamendi
.Synopsis
  Copy Azure SQL Database to a new server
.DESCRIPTION
    This scripts copy a database from an existing serves and:
                                                        - Creates the target resource group if does not exist
                                                        - Creates the target logical SQL server if does not exist
                                                        - Creates firewall rule if it does not exist and parameters targetStartIp and targetEndIp have been defined
                                                        - Copies the database from the source server to the target server

    Pre-requirements:
                    AzModule ----> Install-Module -Name Az 
                    Be connected to Azure ----> Connect-AzAccount 
    Similar samples available in the MSDN documentation: https://docs.microsoft.com/en-us/azure/azure-sql/database/powershell-script-content-guide

.EXAMPLE WITHOUT FIREWALL RULE
    Copy-AzSqlDatabaseDatabaseDifferentServer -SubscriptionId "XXXXXX-XXXXXX-XXXXXX-XXXXXX" `
    -sourceResourceGroupName "source resource group" `
    -sourceServerName "source Azure SQL Server name" `
    -sourceDatabaseName "source database name" `
    -targetResourceGroupname "target resource group name" `
    -targetResourceGroupLocation "target resource group location" `
    -targetServerName "target Azure SQL Server name" `
    -targetDatabaseName "target database name" `
    -targetAdminSqlLogin "target Azure SQL Server user name" `
    -targetAdminSqlPwd "target Azure SQL Server user password" `

   
.EXAMPLE WITH FIREWALL RULE
   Copy-AzSqlDatabaseDatabaseDifferentServer -SubscriptionId "XXXXXX-XXXXXX-XXXXXX-XXXXXX" `
    -sourceResourceGroupName "source resource group" `
    -sourceServerName "source Azure SQL Server name" `
    -sourceDatabaseName "source database name" `
    -targetResourceGroupname "target resource group name" `
    -targetResourceGroupLocation "target resource group location" `
    -targetServerName "target Azure SQL Server name" `
    -targetDatabaseName "target database name" `
    -targetAdminSqlLogin "target Azure SQL Server user name" `
    -targetAdminSqlPwd "target Azure SQL Server user password" `
    -targetFirewallRuleName "target Azure SQL Server firewall rule name"`
    -targetStartIp "target Azure SQL Server start IP rule" `
    -targetEndIp "target Azure SQL Server end IP rule"


#>
[CmdletBinding()]
    param (


        # Connect-AzAccount
        # The SubscriptionId in which to create these objects
        [Parameter(Mandatory=$true)]
        $SubscriptionId = '',
     
        [Parameter(Mandatory=$true)]
        [string]$sourceResourceGroupName ="",
   
        [Parameter(Mandatory=$true)]
        [string]$sourceServerName = "",
        
        [Parameter(Mandatory=$true)]
        [string]$sourceDatabaseName = "",
        
        [Parameter(Mandatory=$true)]
        [string]$targetResourceGroupname ="",
   
        [Parameter(Mandatory=$true)]
        [string]$targetResourceGroupLocation = "",

        [Parameter(Mandatory=$true)]
        [string]$targetServerName = "",
        
        [Parameter(Mandatory=$true)]
        [string]$targetDatabaseName = "",
        
        [Parameter(Mandatory=$true)] 
        [string]$targetAdminSqlLogin = "",

        [Parameter(Mandatory=$true)]
        [string]$targetAdminSqlPwd ="",

        # Optional
        [string]$targetFirewallRuleName ="",

        [string]$targetStartIp ="",
              
        [string]$targetEndIp =""
        

    )

Begin
{
        write-host "Starting restoring database in $TenantId - Server: $targetServerName - Database: $targetDatabaseName"

        # Set subscription 
        Set-AzContext -SubscriptionId $subscriptionId 

        # Define target resource group parameters
        $targetResourceGroupParams = @{     
        "Name" = $targetResourceGroupname 
        "Location" = $targetResourceGroupLocation
        }

        # Define target server parameters
        $targetServerParams = @{     
        "ResourceGroupName" = $targetResourceGroupname 
        "ServerName" = $targetServerName 
        "Location" = $targetResourceGroupLocation
        "SqlAdministratorCredentials" = $(New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $targetAdminSqlLogin, $(ConvertTo-SecureString -String $targetAdminSqlPwd -AsPlainText -Force))
        }


        # Define target firewall rules
        if(($targetFirewallRuleName -ne "") -And ($targetStartIp -ne "") -And  ($targetEndIp -ne ""))
        {
            $targetFirewallRules = @{     
            "ResourceGroupName" = $targetResourceGroupname 
            "ServerName" = $targetServerName 
            "FirewallRuleName" = $targetFirewallRuleName
            "StartIpAddress" = $targetStartIp
            "EndIpAddress" = $targetEndIp
            }

        }
        else
        {
            write-host "Firewall rule parameters have not been defined"
        }

         # Define target database parameters
        $copyDatabaseParams = @{     
        "ResourceGroupName" = $sourceResourceGroupname 
        "ServerName" = $sourceServerName 
        "DatabaseName" = $sourceDatabaseName
        "CopyResourceGroupName" =  $targetResourceGroupname 
        "CopyServerName" = $targetServerName
        "CopyDatabaseName" = $targetDatabaseName 
        }

}

Process 
    {
        
        

    # Create Resource Group
    # Check if exists
        Get-AzResourceGroup @targetResourceGroupParams -ErrorVariable notPresent -ErrorAction SilentlyContinue

        if ($notPresent)
        {
            write-host "Creating Resource Group"
            New-AzResourceGroup @targetResourceGroupParams
        }
        else
        {
            # ResourceGroup exist
            write-host "Resource Group  $targetResourceGroupname already exists."

        }

    # Create Server
    # Check if exists
        Get-AzSqlServer -ResourceGroupName $targetResourceGroupname -ServerName $targetServerName -ErrorVariable ServerNotExist -ErrorAction SilentlyContinue

        if ($ServerNotExist)
        {
            write-host "Creating Server"
            New-AzSqlServer @targetServerParams
           

            if(($targetStartIp -ne "") -And  ($targetEndIp -ne ""))
            {     
                # Check if exists
                Get-AzSqlServerFirewallRule -ResourceGroupName $targetResourceGroupname -ServerName $targetServerName -FirewallRuleName "AllowedIPs" -ErrorVariable RuleNotExist -ErrorAction SilentlyContinue

                if ($RuleNotExist)
                {
                    write-host "Adding firewall rules"
                    New-AzSqlServerFirewallRule @targetFirewallRules
                }
                else
                {
                    # Firewall rule exists
                    write-host "Server $targetServerName already exists."
                }

            }

        }
        else
        {
            # Server exists
            write-host "Server $targetServerName already exists."
        }

    # Create Server Firewall Rule
        if(($targetFirewallRuleName -ne "") -And ($targetStartIp -ne "") -And  ($targetEndIp -ne ""))
        {     
        # Check if exists
            Get-AzSqlServerFirewallRule -ResourceGroupName $targetResourceGroupname -ServerName $targetServerName -FirewallRuleName $targetFirewallRuleName -ErrorVariable RuleNotExist -ErrorAction SilentlyContinue

            if ($RuleNotExist)
            {
                write-host "Adding firewall rules"
                New-AzSqlServerFirewallRule @targetFirewallRules
            }
            else
            {
                # Firewall rule exists
                write-host "Firewall rule $targetFirewallRuleName in $targetServerName already exists."
            }

        }



    # Copy Database
    # Check if exists
        Get-AzSqlDatabase -ResourceGroupName $targetResourceGroupname -ServerName $targetServerName -DatabaseName $targetDatabaseName -ErrorVariable DatabaseDoesNotExist -ErrorAction SilentlyContinue

        if ($DatabaseDoesNotExist)
        {
            # Database doesn't exist
           write-host "Copying Database"

           New-AzSqlDatabaseCopy @copyDatabaseParams

        }
        else
        {

            write-host "Azure Database $targetDatabaseName already exists."

        }

    }
End
{
        write-host "Finish on $(Get-Date)"
}