<#
.SYNOPSIS
    This script is used to create a new local package using the Evergreen library and the PSAppDeployToolkit.

.DESCRIPTION
    The script imports the required modules, downloads the PSAppDeployToolkit, and processes each directory in the specified library.
    For each directory, it imports the App.json, creates a working directory, retrieves the application version using Evergreen,
    copies the PSADT files, downloads the application files using Evergreen, and performs additional tasks based on the Install.json file.

.PARAMETER Library
    The path to the library directory. Default value is ".\Library".

.PARAMETER Path
    The path where the working directories will be created.

.EXAMPLE
    New-LocalPackage.ps1 -Library ".\Library" -Path "C:\WorkingDirectory"

.NOTES
    - This script requires PowerShell version 5.1 or later.
    - The "Evergreen" and "VcRedist" modules must be installed.
    - The Evergreen library must be present in the specified library directory.
    - The PSAppDeployToolkit will be downloaded and extracted to the specified path.
    - The App.json file must be present in each directory in the library.
    - The Install.json file and optional Install.ps1 file must be present in the "Source" directory of each application directory.
#>
#requires -Version 5.1
#requires -Modules "Evergreen"
[CmdletBinding(SupportsShouldProcess = $false)]
param (
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [System.String] $Library = ".\Library",

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [System.String] $Path
)

begin {
    # Import the required modules
    Import-Module -Name "Evergreen", "VcRedist" -Force

    # Import the Evergreen library
    Write-Host "Importing Evergreen library from: $Library"
    $LibraryItems = Get-ChildItem -Path $Library -Directory -ErrorAction "Stop"

    # Download the PSADT
    Write-Host "Download PSAppDeployToolkit"
    $PsadtDir = Join-Path -Path $Path "psadt"
    New-Item -Path $PsadtDir -ItemType "Directory" -Force -ErrorAction "SilentlyContinue" | Out-Null
    $File = Get-EvergreenApp -Name "PSAppDeployToolkit" | Save-EvergreenApp -LiteralPath $PsadtDir -ErrorAction "Stop"
    Expand-Archive -Path $File.FullName -DestinationPath $PsadtDir
    $PsadtSource = Join-Path -Path $PsadtDir -ChildPath "Toolkit"
    Remove-Item -Path "$PsadtSource\Deploy-Application.ps1" -Force
    Remove-Item -Path "$PsadtSource\.vscode" -Recurse -Force
}

process {
    foreach ($App in $LibraryItems) {
        Write-Host "--"
        Write-Host "Processing directory: $($App.FullName)" -ForegroundColor "Yellow"

        # Import the App.json
        $AppJson = Get-Content -Path "$($App.FullName)\App.json" -Raw | ConvertFrom-Json
        Write-Host "Processing app: $($App.FullName)" -ForegroundColor "Cyan"

        # Create a working directory
        $WorkingDir = Join-Path -Path $Path -ChildPath $($AppJson.Application.Name)
        if (Test-Path -Path $WorkingDir) { Remove-Item -Path $WorkingDir -Recurse -Force -ErrorAction "SilentlyContinue" }
        New-Item -Path $WorkingDir -ItemType "Directory" -Force -ErrorAction "SilentlyContinue" | Out-Null
        Write-Host "Working directory: $WorkingDir"

        # Get the application with Evergreen
        Write-Host "Get Evergreen app: $($AppJson.Application.Filter)" -ForegroundColor "Cyan"
        $EvergreenApp = Invoke-Expression -Command $AppJson.Application.Filter
        Write-Host "Evergreen found version: $($EvergreenApp.Version)"

        # Copy the PSADT files
        Write-Host "Copy PSADT files to: $WorkingDir"
        Copy-Item -Path "$PsadtSource\*" -Destination $WorkingDir -Recurse -Force
        Write-Host "Copy $("$($App.FullName)\Deploy-Application.ps1") to: $("$WorkingDir\Deploy-Application.ps1")"
        Copy-Item -Path "$($App.FullName)\Deploy-Application.ps1" -Destination "$WorkingDir\Deploy-Application.ps1"

        Write-Host "Downloading: $($EvergreenApp.URI)"
        $OutFile = $EvergreenApp | Save-EvergreenApp -LiteralPath "$WorkingDir\Files" -ErrorAction "Stop"
        Write-Host "Saved file: $($OutFile.FullName)"

        if (Test-Path -Path $OutFile.FullName) {

            if ($OutFile.FullName -match "\.zip") {
                # Extract the downloaded installer
                Write-Host "Expand zip: $($OutFile.FullName)"
                Expand-Archive -Path $OutFile.FullName -Destination $WorkingDir -Force
                Remove-Item -Path $OutFile.FullName -Force
            }

            if (Test-Path -Path "$($App.FullName)\Source\Install.json") {
                # Copy supporting files
                Write-Host "Copy installation wrapper and supporting files"
                Copy-Item -Path "$($App.FullName)\Source\Install.json" -Destination "$WorkingDir\Install.json"
                if (Test-Path -Path "$($App.FullName)\Install.ps1") {
                    Copy-Item -Path "$($App.FullName)\Install.ps1" -Destination "$WorkingDir\Install.ps1"
                }
                else {
                    Copy-Item -Path "$Library\Install.ps1" -Destination "$WorkingDir\Install.ps1"
                }

                # Read the install.json file
                Write-Host "Build install argument list"
                $Install = Get-Content -Path "$($App.FullName)\Source\Install.json" | ConvertFrom-Json
                $ArgumentList = $Install.InstallTasks.ArgumentList -replace "#SetupFile", $AppJson.PackageInformation.SetupFile
                $ArgumentList = $ArgumentList -replace "#LogName", $AppJson.PackageInformation.SetupFile
                $ArgumentList = $ArgumentList -replace "#LogPath", "$Env:SystemRoot\Logs"
                Write-Host "Setup file: $($AppJson.PackageInformation.SetupFile)"
                Write-Host "Argument list: $ArgumentList"
            }
        }
        else {
            Write-Warning -Message "File not found: $($OutFile.FullName)"
        }
    }
}

end {
}
