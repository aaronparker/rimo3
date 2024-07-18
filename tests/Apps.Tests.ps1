<#
    .SYNOPSIS
        Public Pester function tests.
#>
[OutputType()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseDeclaredVarsMoreThanAssignments", "", Justification = "This OK for the tests files.")]
param ()

BeforeDiscovery {

    # Get the App.json for each app
    $Applications = Get-ChildItem -Path "$env:GITHUB_WORKSPACE\Library" -Include "App.json" -Recurse -ErrorAction "SilentlyContinue" | `
        ForEach-Object { Get-Content -Path $_.FullName | ConvertFrom-Json }
}

Describe -Name "Validate app filters in App.json: <AppJson.Application.Name>" -ForEach $Applications {
    BeforeAll {
        $AppJson = $_
        $EvergreenApp = Invoke-Expression -Command $AppJson.Application.Filter
    }

    Context "Application function <AppJson.Application.Name> should return something" -ForEach $EvergreenApp {
        BeforeAll {
            $Item = $_
        }

        It "Output from <AppJson.Application.Name> should not be null" {
            $Item | Should -Not -BeNullOrEmpty
        }

        It "Output from <AppJson.Application.Name> should return the expected output type" {
            $Item | Should -BeOfType "PSCustomObject"
        }
    }
}
