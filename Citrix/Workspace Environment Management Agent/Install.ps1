# Standalone application install script for VDI environment - (C)2021 Jonathan Pitre & Owen Reynolds, inspired by xenappblog.com

#Requires -Version 5.1
#Requires -RunAsAdministrator

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
$ProgressPreference = "SilentlyContinue"
$ErrorActionPreference = "SilentlyContinue"
$env:SEE_MASK_NOZONECHECKS = 1
$Modules = @("PSADT") # Modules list

Function Get-ScriptDirectory
{
    Remove-Variable appScriptDirectory
    Try
    {
        If ($psEditor) { Split-Path $psEditor.GetEditorContext().CurrentFile.Path } # Visual Studio Code Host
        ElseIf ($psISE) { Split-Path $psISE.CurrentFile.FullPath } # Windows PowerShell ISE Host
        ElseIf ($PSScriptRoot) { $PSScriptRoot } # Windows PowerShell 3.0-5.1
        Else
        {
            Write-Host -Object "Cannot resolve script file's path" -ForegroundColor Red
            Exit 1
        }
    }
    Catch
    {
        Write-Host -Object "Caught Exception: $($Error[0].Exception.Message)" -ForegroundColor Red
        Exit 2
    }
}

Function Initialize-Module
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true)]
        [string]$Module
    )
    Write-Host -Object  "Importing $Module module..." -ForegroundColor Green

    # If module is imported say that and do nothing
    If (Get-Module | Where-Object {$_.Name -eq $Module})
    {
        Write-Host -Object  "Module $Module is already imported." -ForegroundColor Green
    }
    Else
    {
        # If module is not imported, but available on disk then import
        If (Get-Module -ListAvailable | Where-Object {$_.Name -eq $Module})
        {
            $InstalledModuleVersion = (Get-InstalledModule -Name $Module).Version
            $ModuleVersion = (Find-Module -Name $Module).Version
            $ModulePath = (Get-InstalledModule -Name $Module).InstalledLocation
            $ModulePath = (Get-Item -Path $ModulePath).Parent.FullName
            If ([version]$ModuleVersion -gt [version]$InstalledModuleVersion)
            {
                Update-Module -Name $Module -Force
                Remove-Item -Path $ModulePath\$InstalledModuleVersion -Force -Recurse
                Write-Host -Object "Module $Module was updated." -ForegroundColor Green
            }
            Import-Module -Name $Module -Force -Global -DisableNameChecking
            Write-Host -Object "Module $Module was imported." -ForegroundColor Green
        }
        Else
        {
            # Install Nuget
            If (-not(Get-PackageProvider -ListAvailable -Name NuGet))
            {
                Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
                Write-Host -Object "Package provider NuGet was installed." -ForegroundColor Green
            }

            # Add the Powershell Gallery as trusted repository
            If ((Get-PSRepository -Name "PSGallery").InstallationPolicy -eq "Untrusted")
            {
                Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
                Write-Host -Object "PowerShell Gallery is now a trusted repository." -ForegroundColor Green
            }

            # Update PowerShellGet
            $InstalledPSGetVersion = (Get-PackageProvider -Name PowerShellGet).Version
            $PSGetVersion = [version](Find-PackageProvider -Name PowerShellGet).Version
            If ($PSGetVersion -gt $InstalledPSGetVersion)
            {
                Install-PackageProvider -Name PowerShellGet -Force
                Write-Host -Object "PowerShellGet Gallery was updated." -ForegroundColor Green
            }

            # If module is not imported, not available on disk, but is in online gallery then install and import
            If (Find-Module -Name $Module | Where-Object {$_.Name -eq $Module})
            {
                # Install and import module
                Install-Module -Name $Module -AllowClobber -Force -Scope AllUsers
                Import-Module -Name $Module -Force -Global -DisableNameChecking
                Write-Host -Object "Module $Module was installed and imported." -ForegroundColor Green
            }
            Else
            {
                # If the module is not imported, not available and not in the online gallery then abort
                Write-Host -Object "Module $Module was not imported, not available and not in an online gallery, exiting." -ForegroundColor Red
                EXIT 1
            }
        }
    }
}

# Get the current script directory
$appScriptDirectory = Get-ScriptDirectory

# Install and import modules list
Foreach ($Module in $Modules)
{
    Initialize-Module -Module $Module
}

#-----------------------------------------------------------[Functions]------------------------------------------------------------

Function Get-CitrixWEMAgent
{
    [OutputType([System.Management.Automation.PSObject])]
    [CmdletBinding()]
    Param ()
    $DownloadURL = "https://docs.citrix.com/en-us/workspace-environment-management/service/whats-new.html"

    Try
    {
        $DownloadText = (Invoke-WebRequest -Uri $DownloadURL -DisableKeepAlive -UseBasicParsing).RawContent
    }
    Catch
    {
        Throw "Failed to connect to URL: $DownloadURL with error $_."
        Break
    }
    Finally
    {
        $RegEx = "Minimum agent version required: ((?:\d+\.)+(?:\d+))"
        $Version = ($DownloadText | Select-String -Pattern $RegEx).Matches.Groups[1].Value
        $ZipVersion = $Version.Substring(0, $Version.Length - 4)
        $URL = "https://secureportal.citrix.com/Licensing/Downloads/UnrestrictedDL.aspx?DLID=$($appDlNumber)&URL=https://downloads.citrix.com/$($appDlNumber)/Workspace-Environment-Management-Agent-$($ZipVersion).zip"

        if ($Version -and $URL)
        {
            [PSCustomObject]@{
                Name    = 'Citrix Workspace Environment Agent'
                Version = $Version
                Uri     = $URL
            }
        }
    }

}

Function Get-CitrixDownload
{
    <#
.SYNOPSIS
  Downloads a Citrix VDA or ISO from Citrix.com utilizing authentication
.DESCRIPTION
  Downloads a Citrix VDA or ISO from Citrix.com utilizing authentication
  Ryan Butler 2/6/2020 https://github.com/ryancbutler/Citrix/tree/master/XenDesktop/AutoDownload
.PARAMETER dlNumber
  Number assigned to binary download
.PARAMETER dlEXE
  File to be downloaded
.PARAMETER dlPath
  Path to store downloaded file. Must contain following slash (C:\Temp\)
.PARAMETER CitrixUserName
  Citrix.com username
.PARAMETER CitrixPassword
  Citrix.com password
.EXAMPLE
  Get-CitrixDownload -dlNumber "16834" -dlEXE "Citrix_Virtual_Apps_and_Desktops_7_1912.iso" -CitrixUserName "MyCitrixUsername" -CitrixPassword "MyCitrixPassword" -dlPath "C:\Temp\"
#>
    Param(
        [Parameter(Mandatory = $true)]$dlNumber,
        [Parameter(Mandatory = $true)]$dlEXE,
        [Parameter(Mandatory = $true)]$dlPath,
        [Parameter(Mandatory = $true)]$CitrixUserName,
        [Parameter(Mandatory = $true)]$CitrixPassword
    )
    #Initialize Session
    Invoke-WebRequest "https://identity.citrix.com/Utility/STS/Sign-In?ReturnUrl=%2fUtility%2fSTS%2fsaml20%2fpost-binding-response" -SessionVariable websession -UseBasicParsing | Out-Null

    #Set Form
    $Form = @{
        "persistent" = "on"
        "userName"   = $CitrixUserName
        "password"   = $CitrixPassword
    }

    #Authenticate
    Try
    {
        Invoke-WebRequest -Uri ("https://identity.citrix.com/Utility/STS/Sign-In?ReturnUrl=%2fUtility%2fSTS%2fsaml20%2fpost-binding-response") -WebSession $websession -Method POST -Body $form -ContentType "application/x-www-form-urlencoded" -UseBasicParsing -ErrorAction Stop | Out-Null
    }
    Catch
    {
        If ($_.Exception.Response.StatusCode.Value__ -eq 500)
        {
            Write-Verbose "500 returned on auth. Ignoring"
            Write-Verbose $_.Exception.Response
            Write-Verbose $_.Exception.Message
        }
        Else
        {
            Throw $_
        }
    }

    $dlURL = "https://secureportal.citrix.com/Licensing/Downloads/UnrestrictedDL.aspx?DLID=${dlNumber}&URL=https://downloads.citrix.com/${dlNumber}/${dlEXE}"
    $Download = Invoke-WebRequest -Uri $dlURL -WebSession $WebSession -UseBasicParsing -Method GET
    $Webform = @{
        "chkAccept"            = "on"
        "clbAccept"            = "Accept"
        "__VIEWSTATEGENERATOR" = ($Download.InputFields | Where-Object { $_.id -eq "__VIEWSTATEGENERATOR" }).value
        "__VIEWSTATE"          = ($Download.InputFields | Where-Object { $_.id -eq "__VIEWSTATE" }).value
        "__EVENTVALIDATION"    = ($Download.InputFields | Where-Object { $_.id -eq "__EVENTVALIDATION" }).value
    }

    $OutFile = ($dlPath + $dlEXE)
    #Download
    Invoke-WebRequest -Uri $dlURL -WebSession $WebSession -Method POST -Body $Webform -ContentType "application/x-www-form-urlencoded" -UseBasicParsing -OutFile $OutFile
    return $OutFile
}

#----------------------------------------------------------[Declarations]----------------------------------------------------------

$appVendor = "Citrix"
$appName = "Workspace Environment Management Agent"
$appProcesses = @( "Citrix.Wem.Agent.Service", "Citrix.Wem.Agent.LogonService", "VUEMUIAgent", "VUEMAppCmd", "VUEMCmdAgent")
$appInstallParameters = "/quiet Cloud=1" # OnPrem 0 Cloud 1
$appDlNumber = "16122"
$Evergreen = Get-CitrixWEMAgent
$appVersion = $Evergreen.Version
$appURL = $Evergreen.URI
$appZip = Split-Path -Path $appURL -Leaf
$appSetup = "Citrix Workspace Environment Management Agent.exe"
$appDestination = "${env:ProgramFiles(x86)}\Citrix\Workspace Environment Management Agent"
$appScriptURL = "https://raw.githubusercontent.com/JonathanPitre/Scripts/master/Citrix/Reset-WEMCache/Reset-WEMCache.ps1"
$appScript = Split-Path -Path $appScriptURL -Leaf
[boolean]$IsAppInstalled = [boolean](Get-InstalledApplication -Name "$appVendor $appName")
$appInstalledVersion = ((Get-InstalledApplication -Name "$appVendor $appName").DisplayVersion) | Sort-Object -Descending | Select-Object -First 1

#-----------------------------------------------------------[Execution]------------------------------------------------------------

If ([version]$appVersion -gt [version]$appInstalledVersion)
{
    Set-Location -Path $appScriptDirectory
    If (-Not(Test-Path -Path $appVersion)) {New-Folder -Path $appVersion}
    Set-Location -Path $appVersion

    If (-Not(Test-Path -Path $appScriptDirectory\$appVersion\$appSetup) -or (Get-ChildItem).Length -lt 1024kb)
    {
        Write-Log -Message "Citrix credentials for downloading the $appVendor $appName2" -Severity 1 -LogType CMTrace -WriteHost $True
        $CitrixUserName = Read-Host -Prompt "Please supply your Citrix.com username"
        $CitrixPassword1 = Read-Host -Prompt "Please supply your Citrix.com password" -AsSecureString
        $CitrixPassword2 = Read-Host -Prompt "Please supply your Citrix.com password once more" -AsSecureString
        $CitrixPassword1Temp = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($CitrixPassword1))
        $CitrixPassword2Temp = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($CitrixPassword2))

        If ($CitrixPassword1Temp -ne $CitrixPassword2Temp)
        {
            Write-Log -Message "The supplied Citrix passwords missmatch!" -Severity 3 -LogType CMTrace -WriteHost $True
            Exit-Script -ExitCode 1
        }

        Remove-Variable -Name CitrixPassword1Temp, CitrixPassword2Temp
        $CitrixCredentials = New-Object System.Management.Automation.PSCredential ($CitrixUserName, $CitrixPassword1)

        # Verify Citrix credentials
        $CitrixUserName = $CitrixCredentials.UserName
        $CitrixPassword = $CitrixCredentials.GetNetworkCredential().Password

        # Download latest version
        Write-Log -Message "Downloading $appVendor $appName2 $appVersion..." -Severity 1 -LogType CMTrace -WriteHost $True
        Get-CitrixDownload -dlNumber $appDlNumber -dlEXE $appZip -CitrixUserName $CitrixUserName -CitrixPassword $CitrixPassword -dlPath .\
        Expand-Archive -Path $appZip -DestinationPath $appScriptDirectory\$appVersion
        # Move the policy definitions files
        Copy-File -Path "$appScriptDirectory\$appVersion\Agent Group Policies\ADMX\*" -Destination "$appScriptDirectory\PolicyDefinitions" -Recurse
        Copy-File -Path "$appScriptDirectory\$appVersion\Configuration Templates" -Destination "$appScriptDirectory" -Recurse
        # Cleanup
        Remove-Folder -Path "$appScriptDirectory\$appVersion\Agent Group Policies"
        Remove-Folder -Path "$appScriptDirectory\$appVersion\Configuration Templates"
        Remove-File -Path $appZip
    }
    Else
    {
        Write-Log -Message "File(s) already exists, download was skipped." -Severity 1 -LogType CMTrace -WriteHost $True
    }

    Write-Log -Message "Uninstalling previous versions..." -Severity 1 -LogType CMTrace -WriteHost $True
    Get-Process -Name $appProcesses | Stop-Process -Force

    # Download required script
    If (-Not(Test-Path -Path $appScriptDirectory\$appScript))
    {
        Write-Log -Message "Downloading $appName script..." -Severity 1 -LogType CMTrace -WriteHost $True
        Invoke-WebRequest -UseBasicParsing -Uri $appScriptURL -OutFile $appScriptDirectory\$appScript
        Copy-File -Path "$appScriptDirectory\$appScript" -Destination "$env:SystemDrive\Scripts" -Recurse
    }
    Else
    {
        Write-Log -Message "File(s) already exists, download was skipped." -Severity 1 -LogType CMTrace -WriteHost $True
        Copy-File -Path "$appScriptDirectory\$appScript" -Destination "$env:SystemDrive\Scripts" -Recurse
    }

    Write-Log -Message "Installing $appVendor $appName $appVersion..." -Severity 1 -LogType CMTrace -WriteHost $True
    Execute-Process -Path ".\$appSetup" -Parameters $appInstallParameters

    Write-Log -Message "Applying customizations..." -Severity 1 -LogType CMTrace -WriteHost $True

    # Add Windows Defender exclusion(s) - https://docs.citrix.com/en-us/tech-zone/build/tech-papers/antivirus-best-practices.html
    Add-MpPreference -ExclusionProcess "%ProgramFiles(x86)%\Citrix\Workspace Environment Management Agent\AgentGroupPolicyUtility.exe.exe" -Force
    Add-MpPreference -ExclusionProcess "%ProgramFiles(x86)%\Citrix\Workspace Environment Management Agent\Citrix.Wem.Agent.LogonService.exe" -Force
    Add-MpPreference -ExclusionProcess "%ProgramFiles(x86)%\Citrix\Workspace Environment Management Agent\Citrix.Wem.Agent.Service.exe" -Force
    Add-MpPreference -ExclusionProcess "%ProgramFiles(x86)%\Citrix\Workspace Environment Management Agent\VUEMCmdAgent.exe" -Force
    Add-MpPreference -ExclusionProcess "%ProgramFiles(x86)%\Citrix\Workspace Environment Management Agent\VUEMUIAgent.exe" -Force

    # Create schedule task to reset Citrix WEM Cache when Event ID 0 'Cache sync failed with error: SyncFailed' occurs.
    # https://support.citrix.com/article/CTX247927

    # Define CIM object variables
    # This is needed for accessing the non-default trigger settings when creating a schedule task using Powershell
    $Class = cimclass MSFT_TaskEventTrigger root/Microsoft/Windows/TaskScheduler
    $Trigger = $class | New-CimInstance -ClientOnly
    $Trigger.Enabled = $true
    $Trigger.Subscription = "<QueryList><Query Id=`"0`" Path=`"WEM Agent Service`"><Select Path=`"WEM Agent Service`">*[System[(Level=2) and (EventID=0)]] and *[EventData[(Data='Cache sync failed with error: SyncFailed')]]</Select></Query></QueryList>"
    # Define additional variables containing scheduled task action and scheduled task principal
    $A = New-ScheduledTaskAction –Execute powershell.exe -Argument "-NoProfile -NoLogo -NonInteractive -ExecutionPolicy Bypass -File C:\Scripts\Reset-WEMCache.ps1"
    $P = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount
    $S = New-ScheduledTaskSettingsSet

    # Cook it all up and create the scheduled task
    $RegSchTaskParameters = @{
        TaskName    = "Reset Citrix WEM Cache"
        Description = "Reset Citrix WEM Cache when event id 0 'Cache sync failed with error: SyncFailed' occurs"
        TaskPath    = "\"
        Action      = $A
        Principal   = $P
        Settings    = $S
        Trigger     = $Trigger
    }
    Register-ScheduledTask @RegSchTaskParameters
    Write-Log -Message "Scheduled Task to reset Citrix WEM Cache was registered!" -Severity 1 -LogType CMTrace -WriteHost $True

    Write-Log -Message "$appVendor $appName $appVersion was installed successfully!" -Severity 1 -LogType CMTrace -WriteHost $True

}
Else
{
    Write-Log -Message "$appVendor $appName $appInstalledVersion is already installed." -Severity 1 -LogType CMTrace -WriteHost $True
}