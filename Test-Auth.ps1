
$Auth = Get-Content -Path ./auth.json | ConvertFrom-Json

$params = @{
    Uri             = "https://rimo3.okta.com/oauth2/$($Auth.OKTA_STUB)/v1/token"
    Body            = @{
        "grant_type"  = "client_credentials"
        scope         = "access_token"
        client_id     = $Auth.CLIENT_ID
        client_secret = $Auth.CLIENT_SECRET
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
Write-Host "Login successful. Token expires in: $($Token.expires_in)"
