$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Content-Type", "application/json")
$headers.Add("Authorization", "Bearer ***")

$body = @"
{
  `"fileLink`": `"https://drive.google.com/uc?export=download&id=1UQFKLQRZ2HvZy2vxJAKsyZCybUBLre9J`",
  `"displayName`": `"vlc-3.0.8-win64`",
  `"comment`": `"No comment`",
  `"fileName`": `"vlc-3.0.8-win64.msi`",
  `"publisher`": `"VideoLAN`",
  `"name`": `"vlc-3.0.8-win64`",
  `"version`": `"3.0.8`",
  `"installCommand`": `"msiexec /i vlc-3.0.8-win64.msi`",
  `"uninstallCommand`": `"cmd /c`",
  `"progressStep`": 0
}
"@

$response = Invoke-RestMethod 'https://rimo3cloud.com/api/v2/application-packages/upload/manual/link' -Method 'POST' -Headers $headers -Body $body
$response | ConvertTo-Json
