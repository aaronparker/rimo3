#requires -Version 5.1
#requires -Modules "Evergreen"
<#
    Download a specified application via Evergreen and import into Rimo3
#>
[CmdletBinding(SupportsShouldProcess = $true)]
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

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [System.String] $OktaStub = "aus1q1z5zv8Z6Z6QX2p7",

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
        # $WhereBlock = [ScriptBlock]::Create($AppJson.Application.Filter)
        # $EvergreenApp = Get-EvergreenApp -Name $AppJson.Application.Name | `
        #     Where-Object $WhereBlock | `
        #     Select-Object -First 1
        $EvergreenApp = Invoke-Expression -Command $AppJson.Application.Filter
        $EvergreenApp | Format-List

        # Match app to status
        if ($null -eq $EvergreenApp.Filename) {
            $AppStatus = $Status | Where-Object { [System.Version]$_.productVersion -match [System.Version]$EvergreenApp.Version -and $_.fileName -eq $(Split-Path -Path $EvergreenApp.Uri -Leaf) }
        }
        else {
            $AppStatus = $Status | Where-Object { [System.Version]$_.productVersion -match [System.Version]$EvergreenApp.Version -and $_.fileName -eq $EvergreenApp.Filename }
        }

        # If the app doesn't exist, then let's import it
        if ([System.String]::IsNullOrWhiteSpace(($AppStatus.applicationPackageId))) {
            $OutFile = $EvergreenApp | Save-EvergreenApp -LiteralPath $WorkingDir -ErrorAction "Stop"
            Write-Host "Saved file: $($OutFile.FullName)"

            if (Test-Path -Path $OutFile.FullName) {
                #region MSI
                if ($OutFile.FullName -match "\.msi$|\.msix$") {

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
                    if (Test-Path -Path "$($App.FullName)\Install.json") {
                        # Copy supporting files
                        Copy-Item -Path "$($App.FullName)\Install.json" -Destination "$WorkingDir\Install.json"
                        if (Test-Path -Path "$($App.FullName)\Install.ps1") {
                            Copy-Item -Path "$($App.FullName)\Install.ps1" -Destination "$WorkingDir\Install.ps1"
                        }
                        else {
                            Copy-Item -Path "$Library\Install.ps1" -Destination "$WorkingDir\Install.ps1"
                        }
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

                    $params = @{
                        Uri             = $RimoUploadManualUri
                        Method          = "POST"
                        Headers         = @{
                            "accept"        = "application/json"
                            "Authorization" = "Bearer $($Token.access_token)"
                        }
                        Form            = @{
                            "file"              = (Get-Item -Path $ZipFile.FullName)
                            "displayName"      = $AppJson.Information.DisplayName
                            "comment"          = "Imported by Evergreen"
                            "fileName"          = "$(Split-Path -Path $EvergreenApp.URI -Leaf)"
                            "publisher"        = $AppJson.Information.Publisher
                            "name"             = $AppJson.Application.Title
                            "version"          = $EvergreenApp.Version
                            "installCommand"   = $AppJson.Program.InstallCommand
                            "uninstallCommand" = $AppJson.Program.UninstallCommand
                            "tags"             = "Evergreen"
                            "progressStep"     = "2"
                        }
                        ContentType     = "multipart/form-data"
                        UseBasicParsing = $true
                    }
                    $Result = Invoke-RestMethod @params
                    if ($Result.IsSuccessStatusCode -eq $false) {
                        Write-Error -Message $Result.ReasonPhrase
                    }
                }
                #endregion
            }
            else {
                Write-Error -Message "File not found: $($OutFile.FullName)"
            }
        }
        else {
            Write-Host "Application already exists in Rimo3: $($AppJson.Application.Title) $($EvergreenApp.Version)"
            Write-Host ""
        }

        # Remove the variable for the next app
        Remove-Variable -Name "AppStatus" -Force
    }
}
end {
}
