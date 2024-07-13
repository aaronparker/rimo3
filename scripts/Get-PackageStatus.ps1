#requires -Version 5.1
#requires -Modules "Evergreen"
<#
    Get package status for Evergreen apps from Rimo3
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param (
    
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [System.String] $Apps = "EvergreenLibrary.json",

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

    # Import the Evergreen library
    $Library = Get-Content -Path $Apps | ConvertFrom-Json -ErrorAction "Stop"
}
process {
    foreach ($App in $Library.Applications) {
        Write-Host "Processing: $($App.Name)"

        # Get the application with Evergreen
        $WhereBlock = [ScriptBlock]::Create($App.Filter)
        $EvergreenApp = Get-EvergreenApp -Name $App.EvergreenApp | `
            Where-Object $WhereBlock | `
            Select-Object -First 1

        # Get the status of the application sequence
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

        # Match app to status
        if ($null -eq $EvergreenApp.Filename) {
            $AppStatus = $Status | Where-Object { [System.Version]$_.productVersion -match [System.Version]$EvergreenApp.Version -and $_.fileName -eq $(Split-Path -Path $EvergreenApp.Uri -Leaf) }
        }
        else {
            $AppStatus = $Status | Where-Object { [System.Version]$_.productVersion -match [System.Version]$EvergreenApp.Version -and $_.fileName -eq $EvergreenApp.Filename }
        }
        Write-Host "Application id: $($AppStatus.applicationPackageId)"

        if ([System.String]::IsNullOrWhiteSpace(($AppStatus.applicationPackageId))) {
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
        else {
            Write-Host -Message "Application not found in Rimo3"
        }
    }

    $Status
}
