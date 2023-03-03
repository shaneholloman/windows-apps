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
$Modules = @("PSADT", "Evergreen") # Modules list

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
#endregion

#----------------------------------------------------------[Declarations]----------------------------------------------------------

$appName = "ProjectLibre"
$appProcesses = @("ProjectLibre")
$appInstallParameters = "/VERYSILENT /NORESTART"
$appConfigURL = "https://raw.githubusercontent.com/JonathanPitre/Apps/master/ProjectLibre/projectlibre.conf"
$appConfig = Split-Path -Path $appConfigURL -Leaf
$Evergreen = Get-EvergreenApp -Name $appName
$appVersion = $Evergreen.Version
$appURL = $Evergreen.URI
$appSetup = Split-Path -Path $appURL -Leaf
$appDestination = "${env:ProgramFiles}\$appName"
[boolean]$IsAppInstalled = [boolean](Get-InstalledApplication -Name "$appName")
$appInstalledVersion = (Get-InstalledApplication -Name "$appName").DisplayVersion
$appUninstallString = [string]((Get-InstalledApplication -Name "$appName").UninstallString).Split("/")[0]
$appUninstallParameters = "/VERYSILENT /NORESTART"

#-----------------------------------------------------------[Execution]------------------------------------------------------------

If ([version]$appVersion -gt [version]$appInstalledVersion)
{
    Set-Location -Path $appScriptPath
    If (-Not(Test-Path -Path $appVersion))
    {
        New-Folder -Path $appVersion
    }
    Set-Location -Path $appVersion

    # Download latest setup file(s)
    If (-Not(Test-Path -Path $appScriptPath\$appVersion\$appSetup))
    {
        Write-Log -Message "Downloading $appName $appVersion..." -Severity 1 -LogType CMTrace -WriteHost $True
        Invoke-WebRequest -UseBasicParsing -Uri $appURL -OutFile $appSetup
    }
    Else
    {
        Write-Log -Message "File(s) already exists, download was skipped." -Severity 1 -LogType CMTrace -WriteHost $True
    }

    # Uninstall previous versions
    Get-Process -Name $appProcesses | Stop-Process -Force
    If ($IsAppInstalled)
    {
        Write-Log -Message "Uninstalling previous versions..." -Severity 1 -LogType CMTrace -WriteHost $True
        Execute-Process -Path $appUninstallString -Parameters $appUninstallParameters
    }

    # Download required config file
    If (-Not(Test-Path -Path $appScriptPath\$appConfig))
    {
        Write-Log -Message "Downloading $appName config file..." -Severity 1 -LogType CMTrace -WriteHost $True
        Invoke-WebRequest -UseBasicParsing -Uri $appConfigURL -OutFile $appScriptPath\$appConfig
    }
    Else
    {
        Write-Log -Message "File(s) already exists, download was skipped." -Severity 1 -LogType CMTrace -WriteHost $True
    }

    Write-Log -Message "Applying $appName settings to the Default User profile." -Severity 1 -LogType CMTrace -WriteHost $True

    # Copy config file to the default profile
    New-Folder -Path "$envSystemDrive\Users\Default\.projectlibre"
    Copy-File -Path "$appScriptPath\$appConfig" -Destination "$envSystemDrive\Users\Default\.projectlibre\projectlibre.conf"

    # Install latest version
    Write-Log -Message "Installing $appName..." -Severity 1 -LogType CMTrace -WriteHost $True
    Execute-Process -Path .\$appSetup -Parameters $appInstallParameters

    Write-Log -Message "Applying customizations..." -Severity 1 -LogType CMTrace -WriteHost $True

    # Load the Default User registry hive
    Start-Sleep -Seconds 5
    Execute-Process -Path "$envWinDir\System32\reg.exe" -Parameters "LOAD HKLM\DefaultUser $envSystemDrive\Users\Default\NTUSER.DAT" -WindowStyle Hidden

    # Removes software notification
    Set-RegistryKey -Key "HKLM:\DefaultUser\Software\JavaSoft\Prefs\com\projectlibre1\dialog" -Name "validated/License" -Value "true" -Type String
    Set-RegistryKey -Key "HKLM:\DefaultUser\Software\JavaSoft\Prefs\com\projectlibre1\dialog" -Name "user/Email" -Value "true" -Type String
    Set-RegistryKey -Key "HKLM:\DefaultUser\Software\JavaSoft\Prefs\com\projectlibre1\dialog" -Name "/Show/Tip/On/Startup" -Value "false" -Type String

    # Cleanup (to prevent access denied issue unloading the registry hive)
    [GC]::Collect()
    Start-Sleep -Seconds 5

    # Unload the Default User registry hive
    Execute-Process -Path "$envWinDir\System32\reg.exe" -Parameters "UNLOAD HKLM\DefaultUser" -WindowStyle Hidden

    # Cleanup temp files
    Remove-Item -Path "$envSystemDrive\Users\Default\*.LOG1" -Force
    Remove-Item -Path "$envSystemDrive\Users\Default\*.LOG2" -Force
    Remove-Item -Path "$envSystemDrive\Users\Default\*.blf" -Force
    Remove-Item -Path "$envSystemDrive\Users\Default\*.regtrans-ms" -Force

    # Configure application shortcut
    Remove-File -Path "$envCommonDesktop\$appName.lnk" -ContinueOnError $True

    # Go back to the parent folder
    Set-Location ..

    Write-Log -Message "$appName $appVersion was installed successfully!" -Severity 1 -LogType CMTrace -WriteHost $True
}
Else
{
    Write-Log -Message "$appName $appInstalledVersion is already installed." -Severity 1 -LogType CMTrace -WriteHost $True
}