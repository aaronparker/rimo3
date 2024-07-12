#requires -Version 5.1
#requires -Modules "Evergreen"
<#
    Download a specified application via Evergreen and import into Rimo3
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
    [System.String] $OktaStub = "aus1q1z5zv8Z6Z6QX2p7",

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [System.String] $Path
)

begin {
    # Import the Evergreen module
    Import-Module -Name "Evergreen" -Force

    # Define constants
    Set-Variable -Name "Rimo3Url" -Value "https://rimo3cloud.com" -Option "Constant"
    Set-Variable -Name "RimoUploadUri" -Value "$Rimo3Url/api/v2/application-packages/upload" -Option "Constant"
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

        # Download the application with Evergreen
        $WhereBlock = [ScriptBlock]::Create($App.Filter)
        $EvergreenApp = Get-EvergreenApp -Name $App.EvergreenApp | `
            Where-Object $WhereBlock | `
            Select-Object -First 1
        $OutFile = $EvergreenApp | Save-EvergreenApp -LiteralPath $Path -ErrorAction "Stop"
        Write-Host "Saved file: $($OutFile.FullName)"
    
        if (Test-Path -Path $OutFile.FullName) {
            # Compress the downloaded installer
            $FileName = $OutFile.Name -replace " ", ""
            $params = @{
                Path            = $OutFile.FullName
                DestinationPath = "$Path\$($FileName).zip"
                ErrorAction     = "Stop"
            }
            Compress-Archive @params
            $ZipFile = Get-ChildItem -Path "$Path\$($FileName).zip"

            Write-Host "Uploading: $($ZipFile.FullName)"

            # Upload the downloaded installer into Rimo3
            Add-Type -AssemblyName "System.Net.Http"
            $HttpClient = New-Object -TypeName "System.Net.Http.HttpClient"
            $HttpClient.DefaultRequestHeaders.Authorization = New-Object -TypeName "System.Net.Http.Headers.AuthenticationHeaderValue"("Bearer", $($Token.access_token))
            $FileStream = [System.IO.File]::OpenRead($ZipFile.FullName)
            $FileContent = New-Object -TypeName "System.Net.Http.StreamContent" -ArgumentList $FileStream
            $Content = New-Object -TypeName "System.Net.Http.MultipartFormDataContent"
            $Content.Add($FileContent, "file", $ZipFile.FullName)
            $Result = $HttpClient.PostAsync($RimoUploadUri, $Content).Result
            Write-Host $Result.ToString()
        }
        else {
            Write-Error -Message "File not found: $($OutFile.FullName)"
        }
    }
}
