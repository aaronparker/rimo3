<#
    Get package status for Evergreen apps from Rimo3
#>
#requires -Version 5.1
#requires -Modules "Evergreen"
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
    [System.String] $ClientSecret
)

begin {
    # Import the Evergreen module
    Import-Module -Name "Evergreen" -Force

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
    Write-Host "Getting application sequence status"
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

    # Import the Evergreen library
    $LibraryItems = Get-ChildItem -Path $Library -Directory -ErrorAction "Stop"
}
process {
    foreach ($App in $LibraryItems) {
        Write-Host ""
        Write-Host "Processing directory: $($App.FullName)"

        # Import the App.json
        $AppJson = Get-Content -Path "$($App.FullName)\App.json" -Raw | ConvertFrom-Json
        Write-Host "Processing app: $($AppJson.Application.Filter)"

        # Get the application with Evergreen
        $EvergreenApp = Invoke-Expression -Command $AppJson.Application.Filter

        # See if the app has already been imported
        try {
            $AppStatus = $Status | Where-Object { [System.Version]$_.productVersion -match [System.Version]$EvergreenApp.Version -and $_.fileName -eq $AppJson.PackageInformation.SetupFile }
        }
        catch {
            $AppStatus = [System.String]::Empty
        }

        if ([System.String]::IsNullOrWhiteSpace(($AppStatus.applicationPackageId))) {
            Write-Host -Message "Application not found in Rimo3: $($AppJson.Information.DisplayName)"
        }
        else {
            $params = @{
                Uri             = "$Rimo3PackagesUrl/$($AppStatus.applicationPackageId)/sequences"
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
            $Response = Invoke-RestMethod @params
            $Response
        }
    }
}
