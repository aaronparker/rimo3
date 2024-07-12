# Rimo3

Evergreen and Rimo3 Cloud integration proof-of-concept.

## Update Secrets

Add the required secrets to the repository:

* `CLIENT_ID` - Okta client ID
* `CLIENT_SECRET` - secret value to authenticate with the client ID
* `OKTA_STUB` - the stub value used in the Okta authentication URL, e.g. https://rimo3.okta.com/oauth2/**aus44lpmxba6Mxq8M4z7**/v1/token

![.img/repo-secrets.jpeg](.img/repo-secrets.jpeg)

## Run workflow

The GitHub Actions workflow can be starts on the Actions tab. This will import the packages defined in the `Library` directory.

![.img/package-status.jpeg](.img/package-status.jpeg)
