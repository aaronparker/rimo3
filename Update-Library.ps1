[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [System.String] $Source = "/Users/aaron/projects/packagefactory/packages/App",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [System.String] $Library = "/Users/aaron/projects/rimo3/Library"
)

# Get the directories in the source
$Packages = Get-ChildItem -Path $Library -Directory

foreach ($Folder in $Packages.Name) {
    $params = @{
        Path        = "$Source/$Folder/*"
        Destination = "$Library/$Folder"
        Recurse     = $true
        ErrorAction = "Stop"
    }
    Copy-Item @params
}
