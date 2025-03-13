#Requires -Modules Evergreen, VcRedist, PSAppDeployToolkit
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

    # Install PSAppDeployToolkit module
    # Write-Host "Installing PSAppDeployToolkit"
    # Install-Module -Name "PSAppDeployToolkit" -RequiredVersion "4.0.6" -Force
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
        New-Item -Path $WorkingDir -ItemType "Directory" -Force -ErrorAction "SilentlyContinue" | Out-Null
        Write-Host "Working directory: $WorkingDir"

        # Get the application with Evergreen
        Write-Host "Get Evergreen app: $($AppJson.Application.Filter)" -ForegroundColor "Cyan"
        $EvergreenApp = Invoke-Expression -Command $AppJson.Application.Filter
        Write-Host "Evergreen found version: $($EvergreenApp.Version)"

        # Create a PSADT template
        Write-Host "Create PSADT template"
        New-ADTTemplate -Destination "$Env:TEMP\psadt" -Force
        $PsAdtSource = Get-ChildItem -Path "$Env:TEMP\psadt" -Directory -Filter "PSAppDeployToolkit*"
        Copy-Item -Path "$($PsAdtSource.FullName)\*" -Destination $WorkingDir -Recurse -Force
        Remove-Item -Path "$WorkingDir\Invoke-AppDeployToolkit.ps1" -Force

        # Copy custom install files
        Write-Host "Copy $($App.FullName) to: $WorkingDir"
        & "$Env:SystemRoot\System32\robocopy.exe" "$($App.FullName)" "$($WorkingDir)" /S /NP /NJH /NJS /NFL /NDL

        Write-Host "Downloading: $($EvergreenApp.URI)"
        $OutFile = $EvergreenApp | Save-EvergreenApp -LiteralPath "$($WorkingDir)\Files" -ErrorAction "Stop"
        Write-Host "Saved file: $($OutFile.FullName)"

        if (Test-Path -Path $OutFile.FullName) {
            if ($OutFile.FullName -match "\.zip$") {
                # Extract the downloaded installer
                Write-Host "Expand zip: $($OutFile.FullName)"
                Expand-Archive -Path $OutFile.FullName -Destination "$WorkingDir\Files" -Force
                Remove-Item -Path $OutFile.FullName -Force
            }
        }
        else {
            Write-Warning -Message "File not found: $($OutFile.FullName)"
        }
    }
}

end {
}
