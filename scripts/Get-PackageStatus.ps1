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
    [System.String] $ClientSecret,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [System.String] $OktaStub = "aus1q1z5zv8Z6Z6QX2p7"
)

begin {
    # Import the Evergreen module
    Import-Module -Name "Evergreen" -Force

    # Define constants
    Set-Variable -Name "Rimo3Url" -Value "https://rimo3cloud.com" -Option "Constant"
    Set-Variable -Name "RimoPackagesUri" -Value "$Rimo3Url/api/v2/application-packages" -Option "Constant"

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
                Uri             = "$RimoPackagesUri/$($AppStatus.applicationPackageId)/sequences"
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

    $Status
}
