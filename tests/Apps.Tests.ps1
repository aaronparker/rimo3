<#
    .SYNOPSIS
        Public Pester function tests.
#>
[OutputType()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "", Justification = "This OK for the tests files.")]
param ()

BeforeDiscovery {
    # Get the App.json for each app
    $Files = Get-ChildItem -Path "./Library1", "./Library2" -Include "App.json" -Recurse -ErrorAction "Stop"
}

Describe -Name "File - <_>" -ForEach $Files {
    BeforeAll {
        $AppJson = Get-Content -Path $_.FullName | ConvertFrom-Json
        $Name = $AppJson.Application.Name
    }

    Context "App JSON filter should return something: <Name>" {
        It "Output should be a PSCustomObject" {
            { $EvergreenApp = Invoke-Expression -Command $AppJson.Application.Filter } | Should -BeOfType "PSCustomObject"
        }

        It "Output should have 1 or more items" {
            ({ $EvergreenApp = Invoke-Expression -Command $AppJson.Application.Filter }).Count | Should -BeGreaterThan 0
        }
    }
}
