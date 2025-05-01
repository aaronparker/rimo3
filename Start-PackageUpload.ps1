<#
    .SYNOPSIS
    Automates the process of uploading application packages to the Rimo3 Cloud platform.

    .DESCRIPTION
    This script is designed to streamline the process of uploading application packages to the Rimo3 Cloud platform. 
    It authenticates with the Rimo3 API, retrieves the status of existing application packages, and processes new packages 
    by creating working directories, downloading application installers using Evergreen, and uploading the packages to Rimo3.

    .PARAMETER Package
    An array of paths to the application package directories to be processed. Each directory must contain an `App.json` file 
    with metadata about the application.

    .PARAMETER ClientId
    The client ID used for authentication with the Rimo3 API.

    .PARAMETER ClientSecret
    The client secret used for authentication with the Rimo3 API.

    .PARAMETER Path
    The base path where working directories for processing application packages will be created.

    .EXAMPLE
    .\Start-PackageUpload.ps1 -Package "C:\Packages\App1", "C:\Packages\App2" -ClientId "my-client-id" -ClientSecret "my-client-secret" -Path "C:\WorkingDir"

    This example processes two application packages located at `C:\Packages\App1` and `C:\Packages\App2`, authenticates with 
    the Rimo3 API using the provided client ID and secret, and creates working directories under `C:\WorkingDir`.

    .NOTES
    - Requires PowerShell 5.1 or later.
    - Requires the `Evergreen` and `PSAppDeployToolkit` modules.
    - The script uses the Rimo3 API for authentication and package management.
    - Ensure that the `App.json` file in each package directory contains valid metadata for the application.
#>
#Requires -Version 5.1
#Requires -Modules Evergreen, PSAppDeployToolkit
[CmdletBinding(SupportsShouldProcess = $false)]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [System.String[]] $Package,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [System.String] $ClientId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [System.String] $ClientSecret,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [System.String] $Path
)

begin {
    # Import the required modules
    Import-Module -Name "Evergreen", "PSAppDeployToolkit" -Force

    # Define constants
    Set-Variable -Name "Rimo3TokenUrl" -Value "https://rimo3cloud.com/api/v2/connect/token" -Option "Constant"
    Set-Variable -Name "Rimo3BaseUrl" -Value "https://rimo3cloud.com" -Option "Constant"
    Set-Variable -Name "Rimo3PackagesUrl" -Value "$Rimo3BaseUrl/api/v2/application-packages" -Option "Constant"
    Set-Variable -Name "Rimo3UploadUrl" -Value "$Rimo3PackagesUrl/upload" -Option "Constant"
    Set-Variable -Name "Rimo3UploadManualUrl" -Value "$Rimo3UploadUrl/manual" -Option "Constant"

    # Authenticate to the authentication API
    try {
        $EncodedString = [System.Text.Encoding]::UTF8.GetBytes("${ClientId}:$ClientSecret")
        $Base64String = [System.Convert]::ToBase64String($EncodedString)

        $params = @{
            Uri             = $Rimo3TokenUrl
            Body            = "{`"Form-Data`": `"grant_type=client_credentials`"}"
            Headers         = @{
                "Authorization" = "Basic $Base64String"
                "Cache-Control" = "no-cache"
            }
            Method          = "POST"
            UseBasicParsing = $true
            ErrorAction     = "Stop"
        }
        $Token = Invoke-RestMethod @params
        Write-Host "Login successful. Token expires in: $($Token.expires_in)"
    }
    catch {
        Write-Warning -Message "Failed to authenticate to the authentication API. Error: $($_.Exception.Message)"
        break
    }

    # Get the status of the application sequences
    Write-Host "Getting application sequences status from Rimo3"
    $params = @{
        Uri             = $Rimo3PackagesUrl
        Headers         = @{
            "Accept"        = "application/json; utf-8"
            "Authorization" = "Bearer $($Token.access_token)"
            "Content-Type"  = "application/x-www-form-urlencoded"
            "Cache-Control" = "no-cache"
        }
        Method          = "GET"
        UseBasicParsing = $true
        ErrorAction     = "Stop"
    }
    $Status = Invoke-RestMethod @params
    Write-Host "Found $($Status.Count) existing packages."
}

process {
    foreach ($App in $Package) {
        
        # Get the package path
        $PackagePath = Get-Item -Path $App

        Write-Host "--"
        Write-Host "Processing directory: $($PackagePath.FullName)" -ForegroundColor "Yellow"

        # Import the App.json
        $AppJson = Get-Content -Path "$($PackagePath.FullName)\App.json" -Raw | ConvertFrom-Json
        Write-Host "Processing app: $($PackagePath.FullName)" -ForegroundColor "Cyan"

        # Create a working directory
        $WorkingDir = Join-Path -Path $Path -ChildPath $($AppJson.Application.Name)
        if (Test-Path -Path $WorkingDir) { Remove-Item -Path $WorkingDir -Recurse -Force -ErrorAction "SilentlyContinue" }
        New-Item -Path $WorkingDir -ItemType "Directory" -Force -ErrorAction "SilentlyContinue" | Out-Null
        Write-Host "Working directory: $WorkingDir"

        # Get the application with Evergreen
        Write-Host "Get Evergreen app: $($AppJson.Application.Filter)" -ForegroundColor "Cyan"
        $EvergreenApp = Invoke-Expression -Command $AppJson.Application.Filter
        Write-Host "Evergreen found version: $($EvergreenApp.Version)"

        # See if the app has already been imported
        # Cast version number when matching the application
        Write-Host "Filter for existing application in Rimo3 Cloud: $($AppJson.Information.DisplayName)"
        try {
            $AppStatus = $Status | Where-Object {
                [System.Version]$_.productVersion -match [System.Version]$EvergreenApp.Version -and `
                    $_.displayName -eq $AppJson.Information.DisplayName -and `
                    $_.manufacturer -eq $AppJson.Information.Publisher
            }
        }
        catch {
            Write-Warning -Message "Failed to cast version number: $($_.Exception.Message)"
        }

        # Fall back to a direct string comparison
        if ([System.String]::IsNullOrWhiteSpace(($AppStatus.applicationPackageId))) {
            Write-Host "Fallback to direct string compare: $($AppJson.Information.DisplayName)"
            $AppStatus = $Status | Where-Object {
                $_.productVersion -match $EvergreenApp.Version -and `
                    $_.displayName -eq $AppJson.Information.DisplayName -and `
                    $_.manufacturer -eq $AppJson.Information.Publisher
            }
        }

        # If the app doesn't exist, then let's import it
        if ([System.String]::IsNullOrWhiteSpace(($AppStatus.applicationPackageId))) {
            Write-Host "Package not found in Rimo3. Importing: $($AppJson.Information.DisplayName)"

            # Create a PSADT template
            Write-Host "Create PSADT template"
            New-ADTTemplate -Destination "$Env:TEMP\psadt" -Force
            $PsAdtSource = Get-ChildItem -Path "$Env:TEMP\psadt" -Directory -Filter "PSAppDeployToolkit*"
            Copy-Item -Path "$($PsAdtSource.FullName)\*" -Destination $WorkingDir -Recurse -Force
            Remove-Item -Path "$WorkingDir\Invoke-AppDeployToolkit.ps1" -Force

            # Copy custom install files
            Write-Host "Copy $($PackagePath.FullName) to: $WorkingDir"
            & "$Env:SystemRoot\System32\robocopy.exe" "$($PackagePath.FullName)" "$($WorkingDir)" /S /NP /NJH /NJS /NFL /NDL

            Write-Host "Downloading: $($EvergreenApp.URI)"
            $OutFile = $EvergreenApp | Save-EvergreenApp -LiteralPath "$WorkingDir\Files" -ErrorAction "Stop"
            Write-Host "Saved file: $($OutFile.FullName)"

            if (Test-Path -Path $OutFile.FullName) {

                if ($OutFile.FullName -match "\.zip") {
                    # Extract the downloaded installer
                    Write-Host "Expand zip: $($OutFile.FullName)"
                    Expand-Archive -Path $OutFile.FullName -Destination "$WorkingDir\Files" -Force
                    Remove-Item -Path $OutFile.FullName -Force
                }

                # Remove duplicate PSADT files
                Remove-Item -Path "$WorkingDir\PSAppDeployToolkit\Frontend\v4\Invoke-AppDeployToolkit.exe" -ErrorAction "SilentlyContinue"

                # Compress the downloaded installers and supporting files
                Write-Host "Compress zip: $(Join-Path -Path $WorkingDir -ChildPath "$($AppJson.Application.Name).zip")"
                $params = @{
                    Path            = "$WorkingDir\*"
                    DestinationPath = $(Join-Path -Path $WorkingDir -ChildPath "$($AppJson.Application.Name).zip")
                    Force           = $true
                    ErrorAction     = "Stop"
                }
                Compress-Archive @params
                $ZipFile = Get-ChildItem -Path (Join-Path -Path $WorkingDir -ChildPath "$($AppJson.Application.Name).zip")
                
                # Create tags
                $Tags = [System.Collections.ArrayList]::new()
                [void]$Tags.Add('Evergreen')
                #[void]$Tags.Add($AppJson.Information.Publisher)

                try {
                    $params = @{
                        Uri             = $Rimo3UploadManualUrl
                        Method          = "POST"
                        Headers         = @{
                            "accept"        = "application/json"
                            "Authorization" = "Bearer $($Token.access_token)"
                        }
                        Form            = @{
                            "file"             = (Get-Item -Path $ZipFile.FullName)
                            "displayName"      = $AppJson.Information.DisplayName
                            "comment"          = "Imported by Evergreen"
                            "fileName"         = $AppJson.PackageInformation.SetupFile
                            "publisher"        = $AppJson.Information.Publisher
                            "name"             = $AppJson.Application.Title
                            "version"          = $EvergreenApp.Version
                            #"installCommand"   = "$($AppJson.PackageInformation.SetupFile) $ArgumentList"
                            "installCommand"   = $AppJson.Program.InstallCommand
                            "uninstallCommand" = $AppJson.Program.UninstallCommand
                            "tags"             = $Tags
                            "progressStep"     = "2"
                        }
                        ContentType     = "multipart/form-data"
                        UseBasicParsing = $true
                        ErrorAction     = "Continue"
                    }
                    Write-Host "Uploading: $($ZipFile.FullName)"
                    $Result = Invoke-RestMethod @params
                    Write-Host "Package upload OK: $($Result.sequenceIdentifier)"

                    Write-Host "Sleeping for 30 seconds"
                    Start-Sleep -Seconds 30
                }
                catch {
                    Write-Host "WARNING: Package import failed with status code: $($Result.IsSuccessStatusCode)"
                    Write-Warning -Message $_.Exception.Message #$Result.ReasonPhrase
                }
            }
            else {
                Write-Warning -Message "File not found: $($OutFile.FullName)"
            }
        }
        else {
            Write-Host "Application already exists in Rimo3: $($AppJson.Information.DisplayName)"
            Write-Host "Package ID: $($AppStatus.applicationPackageId)"
        }

        # Remove the variable for the next app
        Remove-Variable -Name "AppStatus" -Force
    }
}

end {
    return 0
}
