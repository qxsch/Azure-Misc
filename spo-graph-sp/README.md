# Sharepoint Online Graph API with a Service Principal


## Setup

You will setup 2 service principals in Azure AD.
 * spo-admin-app: This is the service principal that will be used to give sharepoint online permissions to the myapp-backend app. (You can delete this after giving permissions)
 * myapp-backend: This is the service principal that will be used to access the Sharepoint Online Graph API (the application will be using this)
 

1. Create a new App regirstation "myapp-backend" in Azure AD
    1. Configure the following api permissions for graph:
        * Sites.Selected
    1. Memorize the client id
1. Create a new App regirstation "spo-admin-app" in Azure AD
    1. Configure the following api permissions for graph:
        * Sites.FullControl.All
        * Sites.Read.All
        * Sites.ReadWrite.All
    1. Give admin consent 
1. Use the [manageSiteAccess.py](manageSiteAccess.py) script to give permissions to the "myapp-backend" app
   ```bash
   export AZURE_TENANT_ID="<tenant-id>"
   export AZURE_CLIENT_ID="<clientId-of-spo-admin-app>"
   export AZURE_CLIENT_SECRET="<clientSecret-of-spo-admin-app>"

   # search for the site (in case you don't know the site id or url)
   ./manageSiteAccess.py site --search "<name-of-sharepoint-site>"
   # give permission to the site
   ./manageSiteAccess.py create  --site "<url-OR-id-of-sharepoint-site>" --app-id "<clientId-of-myapp-backend>" --app-display-name "myapp-backend" --permission "readwrite"
   ```
1. Go to the sharepoint site and open "Documents" and create a "test" folder right in the root.



## Access
Use the Python script to test access to the Sharepoint Online Graph API
```bash
export SPO_TENANT_ID="<tenant-id>"
export SPO_CLIENT_ID="<clientId-of-myapp-backend>"
export SPO_CLIENT_SECRET="<clientSecret-of-myapp-backend>"
./testAccess.py --spo-site "<url-OR-id-of-sharepoint-site>" --spo-drivename "Documents"
``` 

