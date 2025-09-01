# rhtap-services gitops repo

This repo contains gitops definitions for services needed for testing RHTAP/TSSC like Jenkins, Artifactory, Hive, ...

## Deployment

Steps to deploy these services on new cluster:
1. Edit `./envfile` - fill out the secrets needed.
2. Run `./create_secrets.sh`. This will create the secrets on your cluster
3. Run `./bootstrap.sh`.
    * This script installs Opehsift Gitops and creates initial app-of-apps.

### Artifactory - After deployed on new cluster perform the following to setup.
1. Login to Artifactory-JCR console and complete "Inital Setup"
   Perform the following command to get console url
```
$ echo "https://$(kubectl -n artifactory get route artifactory-ui -o jsonpath='{.spec.host}')"
```
The default username and password for the built-in administrator user is:
admin/password

Accept EULA, fill in a new password and all others can be skipped in the navigation window when you first login to Artifactory-JCR console.

2. Create a Local Docker Repository

Go to `Administration` -> `Repositories` -> `Create a Repository` -> `Local`, Select Package Type `Docker`, fill in `Repository Key` field with `rhtap`, finally click button `Create Local Repository`.

3. Set Me Up - Docker Repository

Go to `Application` -> `JFrog Container Registry` -> `Artifacts`, Click the Docker Repository created in step  `2. Create a Local Docker Repository`, Click `Set Me Up` to set up a generic client

When you input JFrog account password, it generates an identity token and Docker auth contenxt, like below

```
{
        "auths": {
                "https://artifactory-web-artifactory-jcr.apps.rosa.xjiang0212416.jgt9.p3.openshiftapps.com" : {
                        "auth": "xxxxxxxxxxxxxxx",
                        "email": "youremail@email.com"
                }
        }
}
```
<span style="color:red"> Notice: Once `Set Me Up` is done , don't click it again, otherwise the token will be changed.</span>

4. Verify pushing image to Artifactory
Perform the following command to get registry hostname.

```
$ kubectl -n artifactory get route artifactory -o jsonpath='{.spec.host}'
```

Push image to `rhtap` repository on Artifactory server

```
$ podman tag docker.io/mysql:latest <registry hostname>/rhtap/mysql:latest
$ <Copy the Docker auth content into a file, for instance auth.json>
$ podman push --authfile <auth.json> <registry hostname>/rhtap/mysql:latest
```

### Jenkins - After deployed on new cluster perform the following to setup.

1. Get Jenkins console URL
```bash
$ echo "https://$(kubectl -n jenkins get route jenkins -o jsonpath='{.spec.host}')"
```

2. Get admin password
The default username is `admin`. Retrieve the password:
```bash
$ kubectl -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d
```

3. Create API token for admin user
   - Log in to Jenkins console with admin credentials
   - Click on your username (admin) in the upper right corner
   - Click on your username link again to go to your user page
   - Click `Security` from the left sidebar menu
   - In the `API Token` section, click `Add new token` button
   - Enter a token name in the dialog (e.g., "TSSC-Pipeline-Token")
   - Click `Generate` button
   - **Important**: A dialog will display the token with message "Copy this token now, because it cannot be recovered in the future."
   - Copy the token value (use the copy button next to the token)
   - Click `Done` to close the dialog

   Alternative method via REST API:
   ```bash
   # Generate token via API
   curl -X POST "https://$(kubectl -n jenkins get route jenkins -o jsonpath='{.spec.host}')/user/admin/descriptorByName/jenkins.security.ApiTokenProperty/generateNewToken" \
     --user admin:$(kubectl -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d) \
     --data 'newTokenName=TSSC-Pipeline-Token'
   ```

4. (Optional) Verify agent configuration
```bash
# Check if pod template is configured correctly
$ kubectl -n jenkins get configmap jenkins-jenkins-jcasc-config -o yaml | grep -A 20 "podTemplates:"
```

### Nexus - After deployed on new cluster perform the following to setup.

## Setup a Registry

1. Login to Nexus console with the following url
```
$ echo "http://$(kubectl -n nexus get route nexus-ui -o 'jsonpath={.spec.host}')"
```
username is `admin`,  The password can be found in the `/nexus-data/admin.password` file in the nexus pod.

2. When you login to Nexus first time, It will pop up an initial setup widown, you need to fill in new password, accept EULA and choose `Enable Anonymous Access`

3. Click on Settings -> repository -> Repositories -> Create repository and choose docker (hosted) repository.

4. Provide the port number `8082` for HTTP, enable the `Docker v1 api` and enable `Allow anonymous docker pull`. After that,  click on `create` at the bottom of the page.

5. Go to the `Realms` under `Security` on the left navigation bar and click on `Docker Bearer Token Realm` and save the settings.


## Development

### Adding new component

* Create your component `Application` CR in `./app-of-apps` folder.
* Create new folder in `./components` folder holding all the resources of your new component.
