# Rimo3

Evergreen and Rimo3 Cloud integration proof-of-concept.

[![Validate apps](https://github.com/aaronparker/rimo3/actions/workflows/tests.yml/badge.svg)](https://github.com/aaronparker/rimo3/actions/workflows/tests.yml)

## Update Secrets

Add the required secrets to the repository:

* `CLIENT_ID` - Authentication client ID
* `CLIENT_SECRET` - secret value to authenticate with the client ID

![.img/repo-secrets.jpeg](.img/repo-secrets.jpeg)

## Run workflow

The GitHub Actions workflow can be started from the Actions tab. This runs `Start-PackageUpload.ps1` and will import the package selected from the dropdown menu.

![.img/run-workflow.jpeg](.img/run-workflow.png)

## Manually test apps

`New-LocalPackage.ps1` can be used to create packages with PSADT and application binaries for local testing before import into Rimo3 Cloud.
