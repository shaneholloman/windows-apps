# Standalone application install script for VDI environment - (C)2023 Jonathan Pitre

#Requires -Version 5.1
#Requires -RunAsAdministrator

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

#region Initialisations

$ProgressPreference = "SilentlyContinue"
$ErrorActionPreference = "SilentlyContinue"
# Set the script execution policy for this process
Try { Set-ExecutionPolicy -ExecutionPolicy 'ByPass' -Scope 'Process' -Force } Catch {}
# Unblock ps1 script
Get-ChildItem -Recurse *.ps*1 | Unblock-File
$env:SEE_MASK_NOZONECHECKS = 1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[System.Net.WebRequest]::DefaultWebProxy.Credentials = [System.Net.CredentialCache]::DefaultCredentials
$Modules = @("PSADT") # Modules list

Function Get-ScriptPath
{
    <#
    .SYNOPSIS
        Get-ScriptPath returns the path of the current script.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    Param()

    Begin
    {
        Remove-Variable appScriptPath
    }
    Process
    {
        If ($psEditor) { Split-Path -Path $psEditor.GetEditorContext().CurrentFile.Path } # Visual Studio Code
        ElseIf ($MyInvocation.MyCommand.CommandType -eq "ExternalScript") { Split-Path -Path $My$MyInvocation.MyCommand.Source } # PS1 converted to EXE
        ElseIf ($null -ne $HostInvocation) { $HostInvocation.MyCommand.Path } # SAPIEN PowerShell Studio
        ElseIf ($psISE) { Split-Path -Path $psISE.CurrentFile.FullPath } # Windows PowerShell ISE
        ElseIf ($MyInvocation.PSScriptRoot) { $MyInvocation.PSScriptRoot } # Windows PowerShell 3.0+
        ElseIf ($MyInvocation.MyCommand.Path) { Split-Path -Path $MyInvocation.MyCommand.Path -Parent } # Windows PowerShell
        Else
        {
            Write-Host -Object "Unable to resolve script's file path!" -ForegroundColor Red
            Exit 1
        }
    }
}

Function Get-ScriptName
{
    <#
    .SYNOPSIS
        Get-ScriptName returns the name of the current script.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    Param()
    Begin
    {
        Remove-Variable appScriptName
    }
    Process
    {
        If ($psEditor) { Split-Path -Path $psEditor.GetEditorContext().CurrentFile.Path -Leaf } # Visual Studio Code Host
        ElseIf ($psEXE) { [System.Diagnotics.Process]::GetCurrentProcess.Name } # PS1 converted to EXE
        ElseIf ($null -ne $HostInvocation) { $HostInvocation.MyCommand.Name } # SAPIEN PowerShell Studio
        ElseIf ($psISE) { $psISE.CurrentFile.DisplayName.Trim("*") } # Windows PowerShell ISE
        ElseIf ($MyInvocation.MyCommand.Name) { $MyInvocation.MyCommand.Name } # Windows PowerShell
        Else
        {
            Write-Host -Object "Uanble to resolve script's file name!" -ForegroundColor Red
            Exit 1
        }
    }
}

Function Initialize-Module
{
    <#
    .SYNOPSIS
        Initialize-Module install and import modules from PowerShell Galllery.
    .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true)]
        [string]$Module
    )
    Write-Host -Object "Importing $Module module..." -ForegroundColor Green

    # If module is imported say that and do nothing
    If (Get-Module | Where-Object { $_.Name -eq $Module })
    {
        Write-Host -Object "Module $Module is already imported." -ForegroundColor Green
    }
    Else
    {
        # If module is not imported, but available on disk then import
        If ( [boolean](Get-Module -ListAvailable | Where-Object { $_.Name -eq $Module }) )

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
            If (Find-Module -Name $Module | Where-Object { $_.Name -eq $Module })
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

[string]$appScriptPath = Get-ScriptPath # Get the current script path
[string]$appScriptName = Get-ScriptName # Get the current script name

# Install and import modules list
Foreach ($Module in $Modules)
{
    Initialize-Module -Module $Module
}

#endregion

#-----------------------------------------------------------[Functions]------------------------------------------------------------

#region Functions

Function Get-AMDAzureNVv4Driver
{
    [OutputType([System.Management.Automation.PSObject])]
    [CmdletBinding()]
    Param ()
    $DownloadURL = "https://docs.microsoft.com/en-us/azure/virtual-machines/windows/n-series-amd-driver-setup"

    Try
    {
        $DownloadText = (Invoke-WebRequest -Uri $DownloadURL -DisableKeepAlive -UseBasicParsing).Links
    }
    Catch
    {
        Throw "Failed to connect to URL: $DownloadURL with error $_."
        Break
    }
    Finally
    {
        $RegExDriver = "https:\/\/.+AMD-Azure-NVv4-Driver-(.+)\.exe"
        $DriverURL = ($DownloadText | Where-Object href -Match $RegExDriver | Select-Object -ExpandProperty href -First 1)
        $DriverVersion = ($DownloadText | Select-String -Pattern $RegExDriver).Matches.Groups[1].Value

        $RegExUninstaller = "https:\/\/.+AMDCleanupUtility.+\.exe"
        $UninstallerURL = ($DownloadText | Where-Object href -Match $RegExUninstaller | Select-Object -ExpandProperty href -First 1)

        if ($DriverVersion -and $DriverURL)
        {
            [PSCustomObject]@{
                Name         = 'AMD Azure NV4 GPU Driver'
                Architecture = 'x64'
                Type         = 'Exe'
                Version      = $DriverVersion
                Uri          = $DriverURL
            }
        }

        if ($UninstallerURL)
        {
            [PSCustomObject]@{
                Name = 'AMD Cleanup Utility'
                Type = 'Exe'
                Uri  = $UninstallerURL
            }
        }

    }
}

#endregion

#----------------------------------------------------------[Declarations]----------------------------------------------------------


$appVendor = "AMD"
$appVendor2 = "Microsoft"
$appName = "Azure AMD NVv4 GPU Driver"
$appName2 = "Software"
$appProcesses = @("InstallManagerApp.exe")
$appServices = @("AMD Crash Defender Service", "AMD External Events Utility")
$appInstallParameters = "-install"
$Evergreen = Get-AMDAzureNVv4Driver | Where-Object { $_.Name -eq "AMD Azure NV4 GPU Driver" }
$appWebVersion = $Evergreen.Version
$appURL = $Evergreen.URI
$appSetup = Split-Path -Path $appURL -Leaf
$appDestination = ""
$EvergreenUninstaller = Get-AMDAzureNVv4Driver | Where-Object { $_.Name -eq "AMD Cleanup Utility" }
$appUninstallerURL = $EvergreenUninstaller.URI
$appUninstaller = Split-Path -Path $appUninstallerURL -Leaf
$appUninstallParameters = "-silent"
[boolean]$isAppInstalled = [boolean](Get-InstalledApplication -Name "$appVendor $appName2" -Exact)
$appInstalledVersion = (Get-InstalledApplication -Name "$appVendor $appName2" -Exact).DisplayVersion | Select-Object -First 1

#-----------------------------------------------------------[Execution]------------------------------------------------------------

Set-Location -Path $appScriptPath
If (-Not(Test-Path -Path $appWebVersion)) { New-Folder -Path $appWebVersion }

# Download latest setup file(s)
If (-Not(Test-Path -Path $appScriptPath\$appWebVersion\$appSetup))
{
    Write-Log -Message "Downloading $appVendor2 $appName $appWebVersion..." -Severity 1 -LogType CMTrace -WriteHost $True
    Invoke-WebRequest -UseBasicParsing -Uri $appURL -OutFile $appWebVersion\$appSetup
    $appVersion = (Get-FileVersion -File $appWebVersion\$appSetup -ProductVersion).Trim("Attested ")
}
Else
{
    Write-Log -Message "File(s) already exists, download was skipped." -Severity 1 -LogType CMTrace -WriteHost $True
    $appVersion = (Get-FileVersion -File $appWebVersion\$appSetup -ProductVersion).Trim("Attested ")
}

If ([version]$appVersion -gt [version]$appInstalledVersion)
{

    # Download latest setup file(s)
    If (-Not(Test-Path -Path $appScriptPath\$appUninstaller))
    {
        Write-Log -Message "Downloading $appVendor Cleanup Utility..." -Severity 1 -LogType CMTrace -WriteHost $True
        Invoke-WebRequest -UseBasicParsing -Uri $appUninstallerURL -OutFile $appScriptPath\$appUninstaller
    }
    Else
    {
        Write-Log -Message "File(s) already exists, download was skipped." -Severity 1 -LogType CMTrace -WriteHost $True
    }

    # Uninstall previous versions
    Get-Process -Name $appProcesses | Stop-Process -Force
    #Write-Log -Message "Uninstalling previous versions..." -Severity 1 -LogType CMTrace -WriteHost $True
    #Execute-Process -Path $appUninstaller -Parameters $appUninstallParameters

    # Extracting
    If ((Test-Path -Path "$envProgramFiles\7-Zip\7z.exe"))
    {
        Write-Log -Message "Downloading $appVendor Cleanup Utility..." -Severity 1 -LogType CMTrace -WriteHost $True
        Execute-Process -Path "$envProgramFiles\7-Zip\7z.exe" -Parameters "x `"$appScriptPath\$appWebVersion\$appSetup`" -aoa -o`"$appScriptPath\$appWebVersion`""
    }
    Else
    {
        Write-Log -Message "7-Zip must be installed to continue the installation!" -Severity 3 -LogType CMTrace -WriteHost $True
        Exit
    }

    # Install latest version
    Write-Log -Message "Installing $appVendor2 $appName2 $appVersion..." -Severity 1 -LogType CMTrace -WriteHost $True
    Execute-Process -Path $appScriptPath\$appWebVersion\Setup.exe -Parameters $appInstallParameters

    Write-Log -Message "Applying customizations..." -Severity 1 -LogType CMTrace -WriteHost $True

    # Stop and disable unneeded scheduled tasks
    Get-ScheduledTask -TaskName "$appVendor*" | Stop-ScheduledTask
    Get-ScheduledTask -TaskName "$appVendor*" | Disable-ScheduledTask

    # Stop and disable unneeded services
    #Stop-ServiceAndDependencies -Name $appServices[0]
    #Stop-ServiceAndDependencies -Name $appServices[1]
    #Set-ServiceStartMode -Name $appServices[0] -StartMode "Disabled"
    #Set-ServiceStartMode -Name $appServices[1] -StartMode "Disabled"

    # Go back to the parent folder
    Set-Location ..

    Write-Log -Message "$appVendor2 $appName $appVersion was installed successfully!" -Severity 1 -LogType CMTrace -WriteHost $True
}
Else
{
    Write-Log -Message "$appVendor2 $appName $appInstalledVersion is already installed." -Severity 1 -LogType CMTrace -WriteHost $True
}