#!/usr/bin/env python3
import argparse, json, requests, time, urllib, os


class MyArgParser:
    parser = None
    subparsers = None
    sitecmd = None
    listcmd = None
    args = None
    def __init__(self) -> None:
        self.parser = argparse.ArgumentParser(
            prog='manageSiteAccess.py',
            description="Manage Sharepoint Online site access for app registrations",
        )
        self.subparsers = self.parser.add_subparsers(dest='command')

        # site cmd args
        self.sitecmd = self.subparsers.add_parser('site', help='List Sharepoint Online sites or get site by ID or URL')
        siteGrp = self.sitecmd.add_mutually_exclusive_group(required=False)
        siteGrp.add_argument('--search', type=str, help='Search for sites by name')
        siteGrp.add_argument('--site', type=str, help='Get site by ID or URL')
        # generic args for site cmd
        self.sitecmd.add_argument('--tenant-id', default='', type=str, help='The tenant id to authenticate with Sharepoint Online (alternatively use AZURE_TENANT_ID environment variable)')
        self.sitecmd.add_argument('--client-id', default='', type=str, help='The client id to authenticate with Sharepoint Online (alternatively use AZURE_CLIENT_ID environment variable)')
        self.sitecmd.add_argument('--client-secret', default='', type=str, help='The client secret to authenticate with Sharepoint Online (alternatively use AZURE_CLIENT_SECRET environment variable)')
        self.sitecmd.add_argument('--output', choices=['text', 'json'], default='text', help='Output format (default: text)')

        # list cmd args
        self.listcmd = self.subparsers.add_parser('list', help='List permissions for a Sharepoint Online site')
        self.listcmd.add_argument('--site', type=str, required=True, help='Get site by ID or URL')
        self.listcmd.add_argument('--app-id', type=str, help='Filter by ID of the app registration')
        # generic args for list cmd
        self.listcmd.add_argument('--tenant-id', default='', type=str, help='The tenant id to authenticate with Sharepoint Online (alternatively use AZURE_TENANT_ID environment variable)')
        self.listcmd.add_argument('--client-id', default='', type=str, help='The client id to authenticate with Sharepoint Online (alternatively use AZURE_CLIENT_ID environment variable)')
        self.listcmd.add_argument('--client-secret', default='', type=str, help='The client secret to authenticate with Sharepoint Online (alternatively use AZURE_CLIENT_SECRET environment variable)')
        self.listcmd.add_argument('--output', choices=['text', 'json'], default='text', help='Output format (default: text)')

        # create cmd args
        self.createcmd = self.subparsers.add_parser('create', help='Create a new permission for a Sharepoint Online site')
        self.createcmd.add_argument('--site', type=str, required=True, help='Get site by ID or URL')
        self.createcmd.add_argument('--app-id', type=str, required=True, help='ID of the app registration')
        self.createcmd.add_argument('--app-display-name', type=str, required=True, help='Display name of the app registration')
        self.createcmd.add_argument('--permission', type=str, choices=['read', 'write', 'readwrite'], required=True, help='The permission to grant (read, write or readwrite)')
        # generic args for create cmd
        self.createcmd.add_argument('--tenant-id', default='', type=str, help='The tenant id to authenticate with Sharepoint Online (alternatively use AZURE_TENANT_ID environment variable)')
        self.createcmd.add_argument('--client-id', default='', type=str, help='The client id to authenticate with Sharepoint Online (alternatively use AZURE_CLIENT_ID environment variable)')
        self.createcmd.add_argument('--client-secret', default='', type=str, help='The client secret to authenticate with Sharepoint Online (alternatively use AZURE_CLIENT_SECRET environment variable)')
        self.createcmd.add_argument('--output', choices=['text', 'json'], default='text', help='Output format (default: text)')

        # delete cmd args
        self.deletecmd = self.subparsers.add_parser('delete', help='Delete a permission for a Sharepoint Online site')
        self.deletecmd.add_argument('--site', type=str, required=True, help='Get site by ID or URL')
        self.deletecmd.add_argument('--permission-id', type=str, required=True, help='ID of the permission')
        # generic args for delete cmd
        self.deletecmd.add_argument('--tenant-id', default='', type=str, help='The tenant id to authenticate with Sharepoint Online (alternatively use AZURE_TENANT_ID environment variable)')
        self.deletecmd.add_argument('--client-id', default='', type=str, help='The client id to authenticate with Sharepoint Online (alternatively use AZURE_CLIENT_ID environment variable)')
        self.deletecmd.add_argument('--client-secret', default='', type=str, help='The client secret to authenticate with Sharepoint Online (alternatively use AZURE_CLIENT_SECRET environment variable)')
        self.deletecmd.add_argument('--output', choices=['text', 'json'], default='text', help='Output format (default: text)')
    
    def parse_args(self):
        args = self.parser.parse_args()
        # try to set default values from environment variables, if not set in command line
        try:
            if args.tenant_id == '':
                args.tenant_id = os.getenv('AZURE_TENANT_ID', '')
            if args.client_id == '':
                args.client_id = os.getenv('AZURE_CLIENT_ID', '')
            if args.client_secret == '':
                args.spo_client_secret = os.getenv('AZURE_CLIENT_SECRET', '')
        except:
            pass
        return args
    
    def print_help(self, command:str = ''):
        command = str(command).lower()
        if command == 'site':
            self.sitecmd.print_help()
        elif command == 'list':
            self.listcmd.print_help()
        elif command == 'create':
            self.createcmd.print_help()
        elif command == 'delete':
            self.deletecmd.print_help()
        else:
            self.parser.print_help()


class SpoGraphException(RuntimeError):
    pass
class SpoGraphGenericException(SpoGraphException):
    httpResponse : requests.Response
    def __init__(self, message: str, httpResponse : requests.Response):
        super().__init__(message)
        self.httpResponse = httpResponse
    def getHttpCode(self) -> str:
        return self.httpResponse.status_code
    def getHttpText(self) -> str:
        return self.httpResponse.text
class SpoGraphNotFoundException(SpoGraphGenericException):
    pass
class SpoGraphConflictException(SpoGraphGenericException):
    pass


class SpoOauthProvider:
    def getToken(self) -> str:
        raise NotImplementedError()

class SpoAccessTokenOauthProvider(SpoOauthProvider):
    _token: str
    def __init__(self, token: str):
        self._token = str(token)        
    def getToken(self) -> str:
        return self._token

class SpoClientSecretOauthProvider(SpoOauthProvider):
    _tenantId: str
    _clientId: str
    _clientSecret: str
    _autoRefresh: bool
    _token : dict = None
    def __init__(self, tenantId: str, clientId: str, clientSecret: str, autoRefresh: bool = True):
        if not isinstance(tenantId, str) or tenantId == '':
            raise SpoGraphException("Invalid tenantId")
        if not isinstance(clientId, str) or clientId == '':
            raise SpoGraphException("Invalid clientId")
        if not isinstance(clientSecret, str) or clientSecret == '':
            raise SpoGraphException("Invalid clientSecret")
        self._tenantId = str(tenantId)
        self._clientId = str(clientId)
        self._clientSecret = str(clientSecret)
        self._autoRefresh = bool(autoRefresh)

    def refreshToken(self):
        url = "https://login.microsoftonline.com/" + self._tenantId + "/oauth2/v2.0/token"
        data = {
            'grant_type': 'client_credentials',
            'client_id': self._clientId,
            'client_secret': self._clientSecret,
            'scope': 'https://graph.microsoft.com/.default'
        }
        response = requests.post(url, data=data)
        if response.status_code != 200:
            raise SpoGraphException("Failed to get access token: " + response.text)
        self._token = response.json()
        if 'expires_in' in self._token:
            self._token['expires_in'] = time.time() + int(self._token['expires_in'])
        else:
            self._token['expires_in'] = time.time() + 3600
    def getToken(self) -> str:
        if not isinstance(self._token, dict):
            self.refreshToken()
        elif self._autoRefresh:
            if self._token['expires_in'] <= time.time():
                self.refreshToken()
        return self._token['access_token']

class SpoGraphSitePermissionClient:
    _oauthProvider: SpoOauthProvider
    def __init__(self, oauthProvider: SpoOauthProvider):
        self._oauthProvider = oauthProvider
    def _getHeaders(self):
        return {
            'Authorization': f'Bearer {self._oauthProvider.getToken()}'
        }
    def _getFullUrl(self, url: str):
        if url[0] != '/' and url[0] != '?':
            url = '/' + url
        url = 'https://graph.microsoft.com/v1.0/sites' + url
        return url
    def _getRequest(self, url: str):
        response = requests.get(self._getFullUrl(url), headers=self._getHeaders())
        if response.status_code == 404:
            raise SpoGraphNotFoundException(f"Resource not found: {url}", response)
        if response.status_code == 409:
            raise SpoGraphConflictException(f"Conflict: {url}", response)
        if response.status_code != 200:
            raise SpoGraphGenericException(f"Unexpected error: {url}", response)
        try:
            return response.json()
        except Exception as e:
            raise SpoGraphGenericException("Unexpected error at " + str(url) + ": " + str(e) , response)
    def _postRequest(self, url: str, data: dict):
        headers = self._getHeaders()
        headers['Content-Type'] = 'application/json'
        response = requests.post(self._getFullUrl(url), headers=headers, json=data)
        if response.status_code == 404:
            raise SpoGraphNotFoundException(f"Resource not found: {url}", response)
        if response.status_code == 409:
            raise SpoGraphConflictException(f"Conflict: {url}", response)
        if response.status_code != 201 and response.status_code != 200:
            raise SpoGraphGenericException(f"Unexpected error: {url}", response)
        try:
            return response.json()
        except Exception as e:
            raise SpoGraphGenericException("Unexpected error at " + str(url) + ": " + str(e) , response)

    def getSiteIdByUrl(self, url: str):
        return self.getSiteByUrl(url)['id']
    def getSiteByUrl(self, url: str):
        if url.lower().startswith('https://'):
            url = url[8:]
        if url.lower().startswith('http://'):
            url = url[7:]

        url = url.replace('https://', '').replace('http://', '')
        url = url.split('/sites/')

        if len(url) != 2:
            raise SpoGraphException("Invalid URL")
        url[1] = url[1].split('/')[0]

        return self._getRequest('/' + urllib.parse.quote_plus(url[0])  + ':/sites/' + urllib.parse.quote_plus(url[1]))

    def _normalizeSiteId(self, siteId: str):
        siteId = str(siteId).strip()
        if siteId.startswith('https://') or siteId.startswith('http://'):
            siteId = self.getSiteIdByUrl(siteId)
        return siteId  

    def searchSite(self, siteName: str):
        siteName = str(siteName).strip()
        url = "?search=" + urllib.parse.quote_plus(siteName)
        lowername = siteName.lower()
        result = []
        try:
            for r in self._getRequest(url)['value']:
                if str(r['name']).lower() == lowername or str(r['displayName']).lower() == lowername:
                    result.append(r)
        except Exception as e:
            raise SpoGraphException("Failed to search site: " + str(e))
        return result

    def getSite(self, siteId: str):
        siteId = self._normalizeSiteId(siteId)
        url = "/" + siteId
        return self._getRequest(url)

    def getSitePermissions(self, siteId: str):
        siteId = self._normalizeSiteId(siteId)
        url = "/" + siteId + "/permissions"
        result = []
        try:
            for r in self._getRequest(url)['value']:
                result.append(r)
        except Exception as e:
            raise SpoGraphException("Failed to search site: " + str(e))
        return result

    def searchSitePermissionByAppId(self, siteId: str, appId: str):
        siteId = self._normalizeSiteId(siteId)
        appId = str(appId).strip().lower()
        result = []
        try:
            for r in self.getSitePermissions(siteId):
                found = False
                if "grantedToIdentitiesV2" in r:
                    for rr in r["grantedToIdentitiesV2"]:
                        if "application" not in rr:
                            continue
                        if "id" in rr["application"]:
                            if str(rr['application']['id']).lower() == appId:
                                found = True
                                break
                        if "displayName" in rr["application"]:
                            if str(rr['application']['displayName']).lower() == appId:
                                found = True
                                break
                if (not found) and "grantedToIdentities" in r:
                    for rr in r["grantedToIdentitiesV2"]:
                        if "application" not in rr:
                            continue
                        if "id" in rr["application"]:
                            if str(rr['application']['id']).lower() == appId:
                                found = True
                                break
                        if "displayName" in rr["application"]:
                            if str(rr['application']['displayName']).lower() == appId:
                                found = True
                                break
                if found:
                    result.append(r)
        except Exception as e:
            raise SpoGraphException("Failed to search site permission: " + str(e))
        return result
    
    def getSitePermission(self, siteId: str, permissionId: str):
        siteId = self._normalizeSiteId(siteId)
        permissionId = str(permissionId).strip()
        url = "/" + siteId + "/permissions/" + permissionId
        return self._getRequest(url)
    
    def deleteSitePermission(self, siteId: str, permissionId: str):
        siteId = self._normalizeSiteId(siteId)
        permissionId = str(permissionId).strip()
        url = "/" + siteId + "/permissions/" + permissionId
        response = requests.delete(self._getFullUrl(url), headers=self._getHeaders())
        if response.status_code == 404:
            raise SpoGraphNotFoundException(f"Resource not found: {url}", response)
        if response.status_code == 409:
            raise SpoGraphConflictException(f"Conflict: {url}", response)
        if response.status_code != 204:
            raise SpoGraphGenericException(f"Unexpected error: {url}", response)
        return True

    def createSitePermission(self, siteId: str, appId: str, appDisplayName: str, permission: str = 'readwrite'):
        siteId = self._normalizeSiteId(siteId)
        appId = str(appId).strip()
        permission = str(permission).strip()
        if permission not in ['read', 'write', 'readwrite']:
            raise SpoGraphException("Invalid permission: " + permission + " (valid values are: read, write or readwrite)")
        if permission == 'read':
            roles = ["read"]
        else:
            roles = ["read", "write"]
        url = "/" + siteId + "/permissions"
        data = {
            "roles": roles,
            "grantedToIdentities": [
                {
                    "application": {
                        "id": str(appId),
                        "displayName": str(appDisplayName)
                    }
                }
            ]
        }

        return self._postRequest(url, data)



# parse arguments
parser = MyArgParser()
args = parser.parse_args()


def printIt(
    *values: object,
    sep: str | None = " ",
    end: str | None = "\n"
):
    if args.output == 'text':
        print(*values, sep=sep, end=end)

# check if required arguments are set
try:
    if args.output == '':
        pass
    if args.tenant_id == '':
        pass
    if args.client_id == '':
        pass
    if args.client_secret == '':
        pass
except Exception as e:
    parser.print_help(args.command)
    exit(0)

spo = SpoGraphSitePermissionClient(SpoClientSecretOauthProvider(args.tenant_id, args.client_id, args.client_secret))


if args.command == 'site':
    sites = []
    if args.search:
        printIt("Searching for site: " + args.search)
        printIt("")
        sites = spo.searchSite(args.search)
    elif args.site:
        if args.site.lower().startswith('https://') or args.site.lower().startswith('http://'):
            printIt("Getting site by URL: " + args.site)
            printIt("")
            sites = [spo.getSiteByUrl(args.site)]
        else:
            printIt("Getting site by ID: " + args.site)
            printIt("")
            sites = [spo.getSite(args.site)]
    else:
        parser.print_help(args.command)
        print("")
        print("Error: Missing argument --search or --site")
        exit(1)
    if args.output == 'json':
        print(json.dumps(sites, indent=2))
    else:
        for s in sites:
            print("Site-ID: " + str(s['id']))
            print("    Name:        " + str(s['name']))
            print("    DisplayName: " + str(s['displayName']))
            print("    WebUrl:      " + str(s['webUrl']))
elif args.command == 'list':
    perms = []
    if args.app_id:
        printIt("Listing permissions for site: " + args.site + " (and filtered by app-id: " + args.app_id + ")")
        printIt("")
        perms = spo.searchSitePermissionByAppId(args.site, args.app_id)
    else:
        printIt("Listing permissions for site: " + args.site)
        printIt("")
        perms = spo.getSitePermissions(args.site)
    if args.output == 'json':
        print(json.dumps(perms, indent=2))
    else:
        for p in perms:
            print("Permission-ID: " + str(p['id']))
            if 'grantedToIdentitiesV2' in p:
                print("    GrantedToIdentitiesV2:")
                for rr in p['grantedToIdentitiesV2']:
                    if 'application' in rr:
                        if 'displayName' in rr['application']:
                            print("        Application-Id: " + str(rr['application']['id']) + " (" + str(rr['application']['displayName']) + ")")
                        else:
                            print("        Application-Id: " + str(rr['application']['id']))
            if 'grantedToIdentities' in p:
                print("    GrantedToIdentities:")
                for rr in p['grantedToIdentities']:
                    if 'application' in rr:
                        if 'displayName' in rr['application']:
                            print("        Application-Id: " + str(rr['application']['id']) + " (" + str(rr['application']['displayName']) + ")")
                        else:
                            print("        Application-Id: " + str(rr['application']['id']))
elif args.command == 'create':
    printIt("Creating " + args.permission + " permission for site: " + args.site + " (app-id: " + args.app_id + ", app-display-name: " + args.app_display_name + ")")
    printIt("")
    p = spo.createSitePermission(args.site, args.app_id, args.app_display_name, args.permission)
    if args.output == 'json':
        print(json.dumps(p, indent=2))
    else:
        print("Permission-ID: " + str(p['id']))
        if 'grantedToIdentitiesV2' in p:
            print("    GrantedToIdentitiesV2:")
            for rr in p['grantedToIdentitiesV2']:
                if 'application' in rr:
                    if 'displayName' in rr['application']:
                        print("        Application-Id: " + str(rr['application']['id']) + " (" + str(rr['application']['displayName']) + ")")
                    else:
                        print("        Application-Id: " + str(rr['application']['id']))
        if 'grantedToIdentities' in p:
            print("    GrantedToIdentities:")
            for rr in p['grantedToIdentities']:
                if 'application' in rr:
                    if 'displayName' in rr['application']:
                        print("        Application-Id: " + str(rr['application']['id']) + " (" + str(rr['application']['displayName']) + ")")
                    else:
                        print("        Application-Id: " + str(rr['application']['id']))
elif args.command == 'delete':
    printIt("Deleting permission for site: " + args.site + " (permission-id: " + args.permission_id + ")")
    printIt("")
    try:
        spo.deleteSitePermission(args.site, args.permission_id)
        if args.output == 'json':
            print(json.dumps({"Status" : True, "Message" : "Permission deleted"}, indent=2))
        else:
            print("Permission deleted")
    except SpoGraphNotFoundException as e:
        if args.output == 'json':
            print(json.dumps({"Status" : False, "Message" : "Permission not found"}, indent=2))
        else:
            print("Permission not found")
else:
    parser.print_help()
    print("")
    print("Error: Missing command")
    exit(1)


