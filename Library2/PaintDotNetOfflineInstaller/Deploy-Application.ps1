<#
    .SYNOPSIS
    PSAppDeployToolkit - This script performs the installation or uninstallation of an application(s).

    .DESCRIPTION
    - The script is provided as a template to perform an install or uninstall of an application(s).
    - The script either performs an "Install" deployment type or an "Uninstall" deployment type.
    - The install deployment type is broken down into 3 main sections/phases: Pre-Install, Install, and Post-Install.

    The script dot-sources the AppDeployToolkitMain.ps1 script which contains the logic and functions required to install or uninstall an application.

    PSAppDeployToolkit is licensed under the GNU LGPLv3 License - (C) 2024 PSAppDeployToolkit Team (Sean Lillis, Dan Cunningham and Muhammad Mashwani).

    This program is free software: you can redistribute it and/or modify it under the terms of the GNU Lesser General Public License as published by the
    Free Software Foundation, either version 3 of the License, or any later version. This program is distributed in the hope that it will be useful, but
    WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License
    for more details. You should have received a copy of the GNU Lesser General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.

    .PARAMETER DeploymentType
    The type of deployment to perform. Default is: Install.

    .PARAMETER DeployMode
    Specifies whether the installation should be run in Interactive, Silent, or NonInteractive mode. Default is: Interactive. Options: Interactive = Shows dialogs, Silent = No dialogs, NonInteractive = Very silent, i.e. no blocking apps. NonInteractive mode is automatically set if it is detected that the process is not user interactive.

    .PARAMETER AllowRebootPassThru
    Allows the 3010 return code (requires restart) to be passed back to the parent process (e.g. SCCM) if detected from an installation. If 3010 is passed back to SCCM, a reboot prompt will be triggered.

    .PARAMETER TerminalServerMode
    Changes to "user install mode" and back to "user execute mode" for installing/uninstalling applications for Remote Desktop Session Hosts/Citrix servers.

    .PARAMETER DisableLogging
    Disables logging to file for the script. Default is: $false.

    .EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeployMode 'Silent'; Exit $LastExitCode }"

    .EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -AllowRebootPassThru; Exit $LastExitCode }"

    .EXAMPLE
    powershell.exe -Command "& { & '.\Deploy-Application.ps1' -DeploymentType 'Uninstall'; Exit $LastExitCode }"

    .EXAMPLE
    Deploy-Application.exe -DeploymentType "Install" -DeployMode "Silent"

    .NOTES
    Toolkit Exit Code Ranges:
    - 60000 - 68999: Reserved for built-in exit codes in Deploy-Application.ps1, Deploy-Application.exe, and AppDeployToolkitMain.ps1
    - 69000 - 69999: Recommended for user customized exit codes in Deploy-Application.ps1
    - 70000 - 79999: Recommended for user customized exit codes in AppDeployToolkitExtensions.ps1

    .LINK
    https://psappdeploytoolkit.com
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "", Justification = "Variables are used in called functions.")]
[CmdletBinding(SupportsShouldProcess = $false)]
param (
    [Parameter(Mandatory = $false)]
    [ValidateSet('Install', 'Uninstall', 'Repair')]
    [System.String] $DeploymentType = 'Install',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Interactive', 'Silent', 'NonInteractive')]
    [System.String] $DeployMode = 'Silent',

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter] $AllowRebootPassThru = $false,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter] $TerminalServerMode = $false,

    [Parameter(Mandatory = $false)]
    [System.Management.Automation.SwitchParameter] $DisableLogging = $false
)

try {
    ##*===============================================
    ##* VARIABLE DECLARATION
    ##*===============================================

    ##* Do not modify section below
    #region DoNotModify

    ## Variables: Exit Code
    [System.Int32] $MainExitCode = 0

    ## Variables: Script
    [System.String] $DeployAppScriptFriendlyName = 'Deploy Application'
    [System.Version] $DeployAppScriptVersion = [System.Version]'3.10.1'
    [System.String] $DeployAppScriptDate = '05/03/2024'
    [Hashtable] $DeployAppScriptParameters = $PsBoundParameters

    ## Variables: Environment
    if (Test-Path -LiteralPath 'variable:HostInvocation') {
        $InvocationInfo = $HostInvocation
    }
    else {
        $InvocationInfo = $MyInvocation
    }
    [System.String] $ScriptDirectory = Split-Path -Path $InvocationInfo.MyCommand.Definition -Parent

    ## Dot source the required App Deploy Toolkit Functions
    try {
        [System.String] $ModuleAppDeployToolkitMain = "$ScriptDirectory\AppDeployToolkit\AppDeployToolkitMain.ps1"
        if (-not (Test-Path -LiteralPath $ModuleAppDeployToolkitMain -PathType 'Leaf')) {
            throw "Module does not exist at the specified location [$ModuleAppDeployToolkitMain]."
        }
        if ($DisableLogging) {
            . $ModuleAppDeployToolkitMain -DisableLogging
        }
        else {
            . $ModuleAppDeployToolkitMain
        }
    }
    catch {
        if ($MainExitCode -eq 0) {
            [System.Int32] $MainExitCode = 60008
        }
        Write-Error -Message "Module [$ModuleAppDeployToolkitMain] failed to load: `n$($_.Exception.Message)`n `n$($_.InvocationInfo.PositionMessage)" -ErrorAction 'Continue'

        ## Exit the script, returning the exit code to SCCM
        if (Test-Path -LiteralPath 'variable:HostInvocation') {
            $script:ExitCode = $MainExitCode; Exit
        }
        else {
            exit $MainExitCode
        }
    }
    #endregion
    ##* Do not modify section above

    # Read App.json to get details for the app
    $AppJson = Get-Content -Path "$ScriptDirectory\App.json" | ConvertFrom-Json -Depth 10

    ## Variables: Application
    [System.String] $AppVendor = $AppJson.Information.Publisher
    [System.String] $AppName = $AppJson.Information.DisplayName
    [System.String] $AppVersion = $AppJson.PackageInformation.Version
    [System.String] $AppArch = $AppJson.Application.Architecture
    [System.String] $AppLang = $AppJson.Application.Language
    [System.String] $AppRevision = '01'
    [System.String] $AppScriptVersion = '1.0.0'
    [System.String] $AppScriptDate = '19/08/2024'
    [System.String] $AppScriptAuthor = 'Aaron Parker'
    ##*===============================================
    ## Variables: Install Titles (Only set here to override defaults set by the toolkit)
    [System.String] $InstallName = ''
    [System.String] $InstallTitle = ''
    ##*===============================================
    ##* END VARIABLE DECLARATION
    ##*===============================================

    if ($DeploymentType -ine 'Uninstall' -and $DeploymentType -ine 'Repair') {
        ##*===============================================
        ##* PRE-INSTALLATION
        ##*===============================================
        [System.String] $InstallPhase = 'Pre-Installation'


        ##*==============================================================================================
        ##* INSTALLATION
        ##*===============================================
        [System.String] $InstallPhase = 'Installation'

        # Get the installer file specified in the App.json
        Push-Location -Path $dirFiles
        $Installer = Get-ChildItem -Path $AppJson.PackageInformation.SetupFile -Recurse

        # Install the application
        $params = @{
            Action     = "Install"
            Path       = $Installer.FullName
            Parameters = "DESKTOPSHORTCUT=0"
            PassThru   = $true
        }
        Execute-Msi @params
        Pop-Location


        ##*===============================================
        ##* POST-INSTALLATION
        ##*===============================================
        [System.String] $InstallPhase = 'Post-Installation'

        ## Master Wrapper detection
        Set-RegistryKey -Key "HKLM\SOFTWARE\InstalledApps\$($AppJson.Information.DisplayName)"
    }
    elseif ($DeploymentType -ieq 'Uninstall') {

        ##*===============================================
        ##* PRE-UNINSTALLATION
        ##*===============================================
        [System.String] $InstallPhase = 'Pre-Uninstallation'


        ##*===============================================
        ##* UNINSTALLATION
        ##*==============================================================================================
        [System.String] $InstallPhase = 'Uninstallation'

        Remove-MSIApplications -Name 'Paint.NET'

        ##*===============================================
        ##* POST-UNINSTALLATION
        ##*===============================================
        [System.String] $InstallPhase = 'Post-Uninstallation'

        ## Master Wrapper detection
        Remove-RegistryKey -Key "HKLM\SOFTWARE\InstalledApps\$($AppJson.Information.DisplayName)"
    }
    elseif ($DeploymentType -ieq 'Repair') {
        ##*===============================================
        ##* PRE-REPAIR
        ##*===============================================
        [System.String] $InstallPhase = 'Pre-Repair'


        ##*===============================================
        ##* REPAIR
        ##*===============================================
        [System.String] $InstallPhase = 'Repair'


        ##*===============================================
        ##* POST-REPAIR
        ##*===============================================
        [System.String] $InstallPhase = 'Post-Repair'

        ## Master Wrapper detection
        Set-RegistryKey -Key "HKLM\SOFTWARE\InstalledApps\$($AppJson.Information.DisplayName)"
    }

    ##*===============================================
    ##* END SCRIPT BODY
    ##*===============================================

    ## Call the Exit-Script function to perform final cleanup operations
    Exit-Script -ExitCode $MainExitCode
}
catch {
    [System.Int32] $MainExitCode = 0
    [System.String] $MainErrorMessage = "$(Resolve-Error)"
    Write-Log -Message $MainErrorMessage -Severity 3 -Source $DeployAppScriptFriendlyName
    # Show-DialogBox -Text $MainErrorMessage -Icon 'Stop'
    Exit-Script -ExitCode $MainExitCode
}
