<#
    .SYNOPSIS
    Uploads application packages to Rimo3 Cloud.

    .DESCRIPTION
    This script uploads application packages to Rimo3, a cloud-based application management platform. It requires the "Evergreen" module to be installed.

    .PARAMETER Library
    The path to the library directory containing the application packages. Default value is ".\Library".

    .PARAMETER ClientId
    The client ID for authenticating to the Okta API.

    .PARAMETER ClientSecret
    The client secret for authenticating to the Okta API.

    .PARAMETER OktaStub
    The Okta stub for the Okta API URL. Default value is "aus1q1z5zv8Z6Z6QX2p7".

    .PARAMETER Path
    The path where the application packages will be saved.

    .EXAMPLE
    Start-PackageLibraryUpload.ps1 -Library "C:\Applications" -ClientId "12345678" -ClientSecret "abcdefg" -Path "C:\Uploads"
    Uploads application packages from the "C:\Applications" directory to Rimo3 using the specified Okta credentials and saves them to the "C:\Uploads" directory.

    .NOTES
    - This script requires PowerShell version 5.1 or later.
    - The "Evergreen" module must be installed before running this script.
    - Ensure that the Okta credentials provided have the necessary permissions to access the Okta API.
    - The script will authenticate to the Okta API and retrieve an access token before uploading the application packages.
    - The script will check the status of the application sequences in Rimo3 before uploading the packages.
    - The script will process each directory in the library and upload the corresponding application package to Rimo3.
    - The script supports both MSI/MSIX and EXE installers.
    - For MSI/MSIX installers, the script will compress the downloaded installer and upload it to Rimo3.
    - For EXE installers, the script will compress the downloaded installer and supporting files (Install.json and Install.ps1) and upload them to Rimo3.
    - The script will use the Evergreen module to download the application packages based on the filter specified in the App.json file.
    - If an application package with the same version and setup file name already exists in Rimo3, it will not be re-uploaded.
    - The script will display the progress and status of the upload process.
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
    [System.String] $ClientId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [System.String] $ClientSecret,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [System.String] $OktaStub,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [System.String] $Path
)

begin {
    # Import the required modules
    Import-Module -Name "Evergreen", "VcRedist" -Force

    # Define constants
    Set-Variable -Name "Rimo3Url" -Value "https://rimo3cloud.com" -Option "Constant"
    Set-Variable -Name "RimoPackagesUri" -Value "$Rimo3Url/api/v2/application-packages" -Option "Constant"
    Set-Variable -Name "RimoUploadUri" -Value "$RimoPackagesUri/upload" -Option "Constant"
    Set-Variable -Name "RimoUploadManualUri" -Value "$RimoUploadUri/manual" -Option "Constant"

    # Authenticate to the Okta API
    $params = @{
        Uri             = "https://rimo3.okta.com/oauth2/$OktaStub/v1/token"
        Body            = @{
            "grant_type"  = "client_credentials"
            scope         = "access_token"
            client_id     = $ClientId
            client_secret = $ClientSecret
        }
        Headers         = @{
            "Accept"        = "application/json; utf-8"
            "Content-Type"  = "application/x-www-form-urlencoded"
            "Cache-Control" = "no-cache"
        }
        Method          = "POST"
        UseBasicParsing = $true
        ErrorAction     = "Stop"
    }
    $Token = Invoke-RestMethod @params

    # Get the status of the application sequences
    Write-Host "Getting application sequence status"
    $params = @{
        Uri             = $RimoPackagesUri
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

    # Import the Evergreen library
    $LibraryItems = Get-ChildItem -Path $Library -Directory -ErrorAction "Stop"
}
process {
    foreach ($App in $LibraryItems) {
        Write-Host "Processing directory: $($App.FullName)"

        # Import the App.json
        $AppJson = Get-Content -Path "$($App.FullName)\App.json" -Raw | ConvertFrom-Json
        Write-Host "Processing app: $($AppJson.Application.Filter)"

        # Create a working directory
        $WorkingDir = "$Path\$($AppJson.Application.Name)"
        Write-Host "Working directory: $WorkingDir"

        # Download the application with Evergreen
        $EvergreenApp = Invoke-Expression -Command $AppJson.Application.Filter

        # See if the app has already been imported
        $AppStatus = $Status | Where-Object { [System.Version]$_.productVersion -match [System.Version]$EvergreenApp.Version -and $_.fileName -eq $AppJson.PackageInformation.SetupFile }

        # If the app doesn't exist, then let's import it
        if ([System.String]::IsNullOrWhiteSpace(($AppStatus.applicationPackageId))) {
            Write-Host "Importing: $($AppJson.Application.Title) $($EvergreenApp.Version)"
            
            $OutFile = $EvergreenApp | Save-EvergreenApp -LiteralPath $WorkingDir -ErrorAction "Stop"
            Write-Host "Saved file: $($OutFile.FullName)"

            if (Test-Path -Path $OutFile.FullName) {

                if ($OutFile.FullName -match "\.zip") {
                    # Extract the downloaded installer
                    Expand-Archive -Path $OutFile.FullName -Destination $WorkingDir -Force
                    Remove-Item -Path $OutFile.FullName -Force
                }

                #region MSI
                if ($AppJson.PackageInformation.SetupFile -match "\.msi$|\.msix$") {

                    # Compress the downloaded installer
                    $params = @{
                        Path            = "$WorkingDir\*"
                        DestinationPath = "$WorkingDir\$($AppJson.Application.Name).zip"
                        ErrorAction     = "Stop"
                    }
                    Compress-Archive @params
                    $ZipFile = Get-ChildItem -Path "$WorkingDir\$($AppJson.Application.Name).zip"
                    Write-Host "Uploading: $($ZipFile.FullName)"

                    # Upload the MSI/MSIX downloaded installer ZIP into Rimo3
                    Add-Type -AssemblyName "System.Net.Http"
                    $HttpClient = New-Object -TypeName "System.Net.Http.HttpClient"
                    $HttpClient.DefaultRequestHeaders.Authorization = New-Object -TypeName "System.Net.Http.Headers.AuthenticationHeaderValue"("Bearer", $($Token.access_token))
                    $FileStream = [System.IO.File]::OpenRead($ZipFile.FullName)
                    $FileContent = New-Object -TypeName "System.Net.Http.StreamContent" -ArgumentList $FileStream
                    $Content = New-Object -TypeName "System.Net.Http.MultipartFormDataContent"
                    $Content.Add($FileContent, "file", $ZipFile.Name)
                    $Result = $HttpClient.PostAsync($RimoUploadUri, $Content).Result
                    Write-Host $Result.ToString()
                    $FileStream.Close()
                }
                #endregion
                else {
                    #region EXE
                    if (Test-Path -Path "$($App.FullName)\Source\Install.json") {
                        # Copy supporting files
                        Copy-Item -Path "$($App.FullName)\Source\Install.json" -Destination "$WorkingDir\Install.json"
                        if (Test-Path -Path "$($App.FullName)\Install.ps1") {
                            Copy-Item -Path "$($App.FullName)\Install.ps1" -Destination "$WorkingDir\Install.ps1"
                        }
                        else {
                            Copy-Item -Path "$Library\Install.ps1" -Destination "$WorkingDir\Install.ps1"
                        }

                        # Read the install.json file
                        $Install = Get-Content -Path "$($App.FullName)\Source\Install.json" | ConvertFrom-Json
                        $ArgumentList = $Install.InstallTasks.ArgumentList -replace "#SetupFile", $AppJson.PackageInformation.SetupFile
                        $ArgumentList = $ArgumentList -replace "#LogName", $AppJson.PackageInformation.SetupFile
                        $ArgumentList = $ArgumentList -replace "#LogPath", "$Env:SystemRoot\Logs"
                    }

                    # Compress the downloaded installers and supporting files
                    $params = @{
                        Path            = "$WorkingDir\*"
                        DestinationPath = "$WorkingDir\$($AppJson.Application.Name).zip"
                        Force           = $true
                        ErrorAction     = "Stop"
                    }
                    Compress-Archive @params
                    $ZipFile = Get-ChildItem -Path "$WorkingDir\$($AppJson.Application.Name).zip"
                    Write-Host "Uploading: $($ZipFile.FullName)"

                    # Upload the EXE downloaded installer ZIP into Rimo3
                    # Write-Host "Uploading: $($ZipFile.FullName)"
                    # Add-Type -AssemblyName "System.Net.Http"
                    # $HttpClient = New-Object -TypeName "System.Net.Http.HttpClient"
                    # $HttpClient.DefaultRequestHeaders.Authorization = New-Object -TypeName "System.Net.Http.Headers.AuthenticationHeaderValue"("Bearer", $($Token.access_token))
                    # $FileStream = [System.IO.File]::OpenRead($ZipFile.FullName)
                    # $FileContent = New-Object -TypeName "System.Net.Http.StreamContent" -ArgumentList $FileStream
                    # $Content = New-Object -TypeName "System.Net.Http.MultipartFormDataContent"
                    # $Content.Add($FileContent, "file", $ZipFile.Name)

                    # # Add additional properties to the content
                    # $Content.Add((New-Object -TypeName "System.Net.Http.StringContent" -ArgumentList "displayName"), $AppJson.Information.DisplayName)
                    # $Content.Add((New-Object -TypeName "System.Net.Http.StringContent" -ArgumentList "comment"), "Imported by Evergreen")
                    # $Content.Add((New-Object -TypeName "System.Net.Http.StringContent" -ArgumentList "fileName"), "$(Split-Path -Path $EvergreenApp.URI -Leaf)")
                    # $Content.Add((New-Object -TypeName "System.Net.Http.StringContent" -ArgumentList "publisher"), $AppJson.Information.Publisher)
                    # $Content.Add((New-Object -TypeName "System.Net.Http.StringContent" -ArgumentList "name"), $AppJson.Application.Title)
                    # $Content.Add((New-Object -TypeName "System.Net.Http.StringContent" -ArgumentList "version"), $EvergreenApp.Version)
                    # $Content.Add((New-Object -TypeName "System.Net.Http.StringContent" -ArgumentList "installCommand"), $AppJson.Program.InstallCommand)
                    # $Content.Add((New-Object -TypeName "System.Net.Http.StringContent" -ArgumentList "uninstallCommand"), $AppJson.Program.UninstallCommand)
                    # $Content.Add((New-Object -TypeName "System.Net.Http.StringContent" -ArgumentList "tags"), "Evergreen")
                    # $Content.Add((New-Object -TypeName "System.Net.Http.StringContent" -ArgumentList "progressStep"), "2")

                    # # Post the package to the API
                    # $Result = $HttpClient.PostAsync($RimoUploadManualUri, $Content).Result
                    # Write-Host $Result.ToString()
                    # #if ($Result.StatusCode -eq 400) { throw "$($Result.ReasonPhrase)" }
                    # $HttpClient.Dispose()
                    # $FileStream.Close()

                    # Create tags
                    $Tags = [System.Collections.ArrayList]::new()
                    [void]$Tags.Add('Evergreen')
                    [void]$Tags.Add($AppJson.Information.Publisher)

                    $params = @{
                        Uri             = $RimoUploadManualUri
                        Method          = "POST"
                        Headers         = @{
                            "accept"        = "application/json"
                            "Authorization" = "Bearer $($Token.access_token)"
                        }
                        Form            = @{
                            "file"            = (Get-Item -Path $ZipFile.FullName)
                            "displayName"    = $AppJson.Information.DisplayName
                            "comment"        = "Imported by Evergreen"
                            "fileName"        = $AppJson.PackageInformation.SetupFile
                            "publisher"      = $AppJson.Information.Publisher
                            "name"           = $AppJson.Application.Title
                            "version"        = $EvergreenApp.Version
                            "installCommand" = "$($AppJson.PackageInformation.SetupFile) $ArgumentList"
                            #"installCommand"   = $AppJson.Program.InstallCommand
                            #"uninstallCommand" = $AppJson.Program.UninstallCommand
                            "tags"           = $Tags
                            "progressStep"   = "2"
                        }
                        ContentType     = "multipart/form-data"
                        UseBasicParsing = $true
                    }
                    $Result = Invoke-RestMethod @params
                    if ($Result.IsSuccessStatusCode -eq $false) {
                        Write-Error -Message $Result.ReasonPhrase
                    }
                    #endregion
                }
            }
            else {
                Write-Error -Message "File not found: $($OutFile.FullName)"
            }
        }
        else {
            Write-Host "Application already exists in Rimo3: $($AppJson.Application.Title) $($EvergreenApp.Version)"
        }

        # Remove the variable for the next app
        Remove-Variable -Name "AppStatus" -Force
    }
}
end {
}
