<#
.History
   01/06/2021 - 1.0 - Initial release - David Alzamendi - https://techtalkcorner.com
.Synopsis
   Creates, moves or removes Dns Name for Azure SQL Database and Azure Synapse Analytics SQL Pools
.DESCRIPTION
    This script sets an Azure SQL admin using the following cmdlets
    Pre-requirements:
                    AzModule ----> Install-Module -Name Az.Sql
                    Be connected to Azure ----> Connect-AzAccount 
    Module descriptions are in https://docs.microsoft.com/en-us/powershell/module/az.sql/set-azsqlserveractivedirectoryadministrator?view=azps-5.6.0

.EXAMPLE
Create
    Configure-AzSql-DnsAlias -DnsOperation "Create" -ResourceGroupName "" -ServerName "" -DnsName "" 
Move
    Configure-AzSql-DnsAlias -DnsOperation "Move"  -ResourceGroupName "" -ServerName "" -DnsName "" -SubscriptionName "" -TargetResourceGroupName "" -TargetServerName ""
Remove 
    Configure-AzSql-DnsAlias -DnsOperation "Remove" -ResourceGroupName "" -ServerName "" -DnsName "" 
   #>
[CmdletBinding()]
param (

    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName ="",
   
    [Parameter(Mandatory=$true)]
    [string]$ServerName = "", # Source Server Name when moving the DNS Name

    # Server DNS Alias name cannot be empty or null. It can only be made up of lowercase letters 
    # 'a'-'z', the numbers 0-9 and the hyphen. The hyphen may not lead or trail in the name.
    [Parameter(Mandatory=$true)]
    [string]$DnsName= "", 
    
    [Parameter(Mandatory=$true)]
    [ValidateSet('Create', 'Move','Remove')]
    [string]$DnsOperation = "",

    # Parameters required to move Dns Name to a different server:
    [Parameter(Mandatory=$false)]
    [string]$SubscriptionName = "", # Required when moving the Dns Name to a different server

    [Parameter(Mandatory=$false)]
    [string]$TargetResourceGroupName = "", # Target resource group name

    [Parameter(Mandatory=$false)]
    [string]$TargetServerName = "" # Target server name


)
    
   
Begin
    {
          $ServiceName = "Azure Dns Name - DnsOperation: $DnsOperation"

          write-host "Starting $ServiceName on $(Get-Date)"
        
         switch($DnsOperation) 
         {
             'Create' {
                   # Create parameters
                   write-host "Create: getting parameters on $(Get-Date)"
                   $AzureParams = @{
                    "ServerName" = $ServerName
                    "ResourceGroupName" = $ResourceGroupName
                    "Name" = $DnsName
                    }
             }
             'Move' {                   
                    # Get subscription information      
                    write-host "Move: getting parameters on $(Get-Date)"
                    $SubscriptionId = Get-AzSubscription -SubscriptionName $SubscriptionName
                   
                   # Create parameters
                   write-host "Move: getting parameters on $(Get-Date)"
                   $AzureParams = @{
                    "SourceServerName" = $ServerName
                    "SourceServerSubscriptionId" = $SubscriptionId.Id
                    "SourceServerResourceGroup" = $ResourceGroupName
                    "Name" = $DnsName
                    "TargetServerName" = $TargetServerName
                    "ResourceGroupName" = $TargetResourceGroupName
                    }
             }
             'Remove' {
                   # Create parameters
                   write-host "Remove: getting parameters on $(Get-Date)"
                   $AzureParams = @{
                    "ServerName" = $ServerName
                    "ResourceGroupName" = $ResourceGroupName
                    "Name" = $DnsName
                    }
             }

             default {
                Write-Error "Something is wrong"
             }
         }



    }

Process 
    {


    switch($DnsOperation) 
    {
        'Create' {
            #Check if exists
            write-host "Create: verifying if alias exists on $(Get-Date)"
            $GetExisting = Get-AzSqlServerDnsAlias -ResourceGroupName $ResourceGroupName -ServerName  $ServerName -Name $DnsName -ErrorVariable DoesNotExist -ErrorAction SilentlyContinue

            if($DoesNotExist) {
                write-host "Start creation of Dns Alias on $(Get-Date)"
                
                New-AzSqlServerDnsAlias @AzureParams
            } else {
                Throw "Dns Name $DnsName in Server $ServerName exists"
            }
        }
        'Move' {
            #Check if exists
            write-host "Create: verifying if servers exist on $(Get-Date)"
            $GetExistingSource = Get-AzSqlServer -ResourceGroupName $ResourceGroupName -Name $ServerName -ErrorVariable DoesNotExist -ErrorAction SilentlyContinue
            $GetExistingTarget = Get-AzSqlServer -ResourceGroupName $TargetResourceGroupName -Name $TargetServerName -ErrorVariable DoesNotExist -ErrorAction SilentlyContinue

            if($DoesNotExist) {
                Throw "One of the severs does not exist exist"
            }
            else {
                write-host "Start re-assignment of Dns Alias on $(Get-Date)"

                Set-AzSqlServerDnsAlias @AzureParams
            }
        }
        'Remove' {
            #Check if exists
            write-host "Remove: verifying if alias exists on $(Get-Date)"
            $GetExisting = Get-AzSqlServerDnsAlias -ResourceGroupName $ResourceGroupName -ServerName $ServerName -Name $DnsName -ErrorVariable DoesNotExist -ErrorAction SilentlyContinue

            if($DoesNotExist) {
                
                Throw "Dns Name $DnsName in Server $ServerName does not exist"

            } else {
                write-host "Removing Dns Alias on $(Get-Date)"

                Remove-AzSqlServerDnsAlias -Force @AzureParams 
            }
        }
    }
}
End
    {
        write-host "Finish on $(Get-Date)"
    }
