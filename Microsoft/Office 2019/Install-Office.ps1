﻿# Standalone application install script for VDI environment - (C)2021 Jonathan Pitre & Owen Reynolds, inspired by xenappblog.com

#Requires -Version 5.1
#Requires -RunAsAdministrator

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
$ProgressPreference = "SilentlyContinue"
$ErrorActionPreference = "SilentlyContinue"
$env:SEE_MASK_NOZONECHECKS = 1
$Modules = @("PSADT", "Evergreen") # Modules list

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

#----------------------------------------------------------[Declarations]----------------------------------------------------------

$appVendor = "Microsoft"
$appName = "Office"
$appMajorVersion = "2019"
$appSetup = "setup.exe"
$appProcesses = @("OUTOOK", "EXCEL", "MSACCESS", "WINPROJ", "LYNC", "VISIO", "ONENOTE", "POWERPNT", "MSPUB")
$appConfig = "$appScriptDirectory\Office2019-x64-VDI.xml"
$appBitness = ([xml](Get-Content -Path $appConfig)).SelectNodes("//Add/@OfficeClientEdition").Value
$appDownloadParameters = "/download .\$appConfig"
$appInstallParameters = "/configure .\$appConfig"
$Evergreen = Get-EvergreenApp -Name Microsoft365Apps | Where-Object {$_.Channel -eq "PerpetualVL2019"}
$appVersion = $Evergreen.Version
$appURL = $Evergreen.URI
$appDestination = "$env:ProgramFiles\Microsoft Office\root\Office16"
[boolean]$IsAppInstalled = [boolean](Get-InstalledApplication -Name "$appVendor $appName .+ $appMajorVersion" -RegEx)
$appInstalledVersion = (Get-InstalledApplication -Name "$appVendor $appName .* $appMajorVersion" -RegEx).DisplayVersion

#-----------------------------------------------------------[Execution]------------------------------------------------------------

If ([version]$appVersion -gt [version]$appInstalledVersion) {
    Set-Location -Path $appScriptDirectory

    If (-Not(Test-Path -Path $appScriptDirectory\$appSetup)) {
        Write-Log -Message "Downloading the latest version of  $appVendor $appName Deployment Tool (ODT)..." -Severity 1 -LogType CMTrace -WriteHost $True
        Invoke-WebRequest -UseBasicParsing -Uri $appURL -OutFile $appSetup
    }
    Else {
        Write-Log -Message "File(s) already exists, download was skipped." -Severity 1 -LogType CMTrace -WriteHost $True
    }

    $appSetupVersion = (Get-Command .\$appSetup).FileVersionInfo.FileVersion

    Write-Log -Message "Uninstalling previous versions..." -Severity 1 -LogType CMTrace -WriteHost $True
    Get-Process -Name $appProcesses | Stop-Process -Force
    # https://github.com/OfficeDev/Office-IT-Pro-Deployment-Scripts/blob/master/Office-ProPlus-Deployment/Remove-PreviousOfficeInstalls/Remove-PreviousOfficeInstalls.ps1
    .\Remove-PreviousOfficeInstalls\Remove-PreviousOfficeInstalls.ps1 -RemoveClickToRunVersions $true -Force $true -Remove2016Installs $true -NoReboot $true

    If (-Not(Test-Path -Path .\$appSetupVersion)) {New-Folder -Path $appSetupVersion}
    Copy-File .\$appConfig, $appSetup -Destination $appSetupVersion -ContinueFileCopyOnError $True
    Set-Location -Path .\$appSetupVersion

    If (-Not(Test-Path -Path .\Office\Data\v$appBitness.cab)) {
        Write-Log -Message "Downloading $appVendor $appName $appMajorVersion $appBitness via ODT $appSetupVersion..." -Severity 1 -LogType CMTrace -WriteHost $True
        Execute-Process -Path .\$appSetup -Parameters $appDownloadParameters -PassThru
    }
    Else {
        Write-Log -Message "File(s) already exists, download was skipped." -Severity 1 -LogType CMTrace -WriteHost $True
    }

    Write-Log -Message "Installing $appVendor $appName $appMajorVersion $appBitness..." -Severity 1 -LogType CMTrace -WriteHost $True
    Execute-Process -Path .\$appSetup -Parameters $appInstallParameters -Passthru
    Get-Process -Name OfficeC2RClient | Stop-Process -Force

    Write-Log -Message "Applying customizations..." -Severity 1 -LogType CMTrace -WriteHost $True
    Rename-Item -Path "$envCommonStartMenuPrograms\OneNote 2016.lnk" -NewName "$envCommonStartMenuPrograms\OneNote.lnk"
    Get-ScheduledTask -TaskName "$appName*" | Stop-ScheduledTask
    Get-ScheduledTask -TaskName "$appName*" | Disable-ScheduledTask

    # Go back to the parent folder
    Set-Location ..

    Write-Log -Message "$appVendor $appName $appMajorVersion $appBitness was successfully installed!" -Severity 1 -LogType CMTrace -WriteHost $True
}
Else {
    Write-Log -Message "$appVendor $appName $appMajorVersion $appBitness is already installed." -Severity 1 -LogType CMTrace -WriteHost $True
}