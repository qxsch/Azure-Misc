#!/usr/bin/env python3
import os, io, time, datetime, json, argparse, requests, urllib
from mimetypes import MimeTypes
from azure.identity import DefaultAzureCredential, ChainedTokenCredential


parser = argparse.ArgumentParser(
    prog='testAccess.py',
    description="Test Access to Sharepoint Online."
)
parser.add_argument('--spo-site', type=str, required=True, help='The ID or URL of the Sharepoint Online site')
parser.add_argument('--spo-drivename', type=str, default='Documents', help='The drive name of the Sharepoint Online site')
parser.add_argument('--spo-subpath', type=str, default='', help='The sub path of the Sharepoint Online site')
authParserGrp = parser.add_argument_group("Default Authentication")
authParserGrp.add_argument('--spo-use-default-credentials', action='store_true', help='Use the default credentials to authenticate with Sharepoint Online')
authParserGrp2 = parser.add_argument_group("Direct credentials-based authentication")
authParserGrp2.add_argument('--spo-tenant-id', default='', type=str, help='The tenant id to authenticate with Sharepoint Online (alternatively use SPO_TENANT_ID environment variable)')
authParserGrp2.add_argument('--spo-client-id', default='', type=str, help='The client id to authenticate with Sharepoint Online (alternatively use SPO_CLIENT_ID environment variable)')
authParserGrp2.add_argument('--spo-client-secret', default='', type=str, help='The client secret to authenticate with Sharepoint Online (alternatively use SPO_CLIENT_SECRET environment variable)')
args = parser.parse_args()

if args.spo_tenant_id == '':
    args.spo_tenant_id = os.getenv('SPO_TENANT_ID', '')
if args.spo_client_id == '':
    args.spo_client_id = os.getenv('SPO_CLIENT_ID', '')
if args.spo_client_secret == '':
    args.spo_client_secret = os.getenv('SPO_CLIENT_SECRET', '')
if args.spo_use_default_credentials and (args.spo_tenant_id != '' or args.spo_client_id != '' or args.spo_client_secret != ''):
    parser.print_help()
    print("")
    print("")
    print("Invalid arguments: --spo-use-default-credentials and --spo-tenant-id/--spo-client-id/--spo-client-secret are mutually exclusive")
    exit(1)
if (not args.spo_use_default_credentials) and (args.spo_tenant_id == '' or args.spo_client_id == '' or args.spo_client_secret == ''):
    parser.print_help()
    print("")
    print("")
    print("Invalid arguments: either use --spo-use-default-credentials  or  provide --spo-tenant-id, --spo-client-id and --spo-client-secret")
    exit(1)


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

class SpoChainedTokenCredentialOauthProvider(SpoOauthProvider):
    _tokenCredentials: ChainedTokenCredential
    _cachedToken = None
    _autoRefresh: bool
    def __init__(self, tokenCredentials: ChainedTokenCredential, autoRefresh: bool = True):
        self._tokenCredentials = tokenCredentials
        self._autoRefresh = bool(autoRefresh)
    def refreshToken(self):
        self._cachedToken = self._tokenCredentials.get_token('https://graph.microsoft.com/.default')
    def getToken(self) -> str:
        if self._cachedToken is None:
            self.refreshToken()
        elif self._autoRefresh:
            if self._cachedToken.expires_on <= time.time():
                self.refreshToken()
        return self._cachedToken.token
    
class SpoClientSecretOauthProvider(SpoOauthProvider):
    _tenantId: str
    _clientId: str
    _clientSecret: str
    _autoRefresh: bool
    _token : dict = None
    def __init__(self, tenantId: str, clientId: str, clientSecret: str, autoRefresh: bool = True):
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


class SpoGraphFileApi:
    _token: str
    _siteId: str
    _driveId : str
    _driveName: str
    _subPath: str

    def __init__(
            self,
            accessToken : (SpoOauthProvider | str),
            siteId: str,
            driveName: str = "Documents",
            subPath: str = ""
    ):
        if isinstance(accessToken, SpoOauthProvider):
            self._token = accessToken
        else:
            self._token = SpoAccessTokenOauthProvider(str(accessToken))
        self._siteId = str(siteId)
        self._subPath = str(subPath)
        if self._subPath.startswith('/'):
            self._subPath = self._subPath[1:]
        if self._subPath.endswith('/'):
            self._subPath = self._subPath[:-1]
        if self._siteId.lower().startswith('https://') or self._siteId.lower().startswith('https://'):
            self._siteId = self.getSiteIdByUrl(self._siteId)
        self.setDriveName(driveName)

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

        response = requests.get(
            'https://graph.microsoft.com/v1.0/sites/' + urllib.parse.quote_plus(url[0])  + ':/sites/' + urllib.parse.quote_plus(url[1]),
            headers={
                'Authorization': 'Bearer ' + str(self._token.getToken())
            }
        )
        if response.status_code != 200:
            raise SpoGraphGenericException("Failed to list sites", response)
        try:
            j = response.json()
            if 'id' not in j:
                raise SpoGraphException("Missing id key in response")
        except Exception as e:
            raise SpoGraphGenericException("Failed to list sites: " + str(e), response)
        return j

    def listAllDrives(self):
        response = requests.get(
            'https://graph.microsoft.com/v1.0/sites/' + urllib.parse.quote_plus(self._siteId) + '/drives',
            headers={
                'Authorization': 'Bearer ' + str(self._token.getToken())
            }
        )
        if response.status_code != 200:
            raise SpoGraphGenericException("Failed to list drive items", response)
        try:
            j = response.json()
            if 'value' in j:
                j = j['value']
            else:
                raise SpoGraphException("Missing value key in response")
        except Exception as e:
            raise SpoGraphGenericException("Failed to list drive items: " + str(e), response)
        return j
    
    def listAllDriveNames(self):
        names = []
        for d in self.listAllDrives():
            names.append(d['name'])
        return names
    def getDriveId(self):
        return self._driveId
    def getDriveName(self):
        return self._driveName
    def setDriveName(self, driveName: str):
        driveName = str(driveName).lower()
        for d in self.listAllDrives():
            if str(d['name']).lower() == driveName:
                self._driveName = driveName
                self._driveId = d['id']
                return self
        raise SpoGraphException("Drive not found")

    def getCombinedPath(self, path: str = ""):
        if path != "":
            if path.startswith('/'):
                path = path[1:]
            if self._subPath != "":
                return self._subPath + '/' + path
            else:
                return path
        else:
            return self._subPath

    def getPathInfo(self, path: str = ""):
        response = requests.get(
            'https://graph.microsoft.com/v1.0/drives/' + urllib.parse.quote_plus(self._driveId) + '/root:/' + urllib.parse.quote_plus(self.getCombinedPath(path)),
            headers={
                'Authorization': 'Bearer ' + str(self._token.getToken())
            }
        )
        if response.status_code == 200:
            j = response.json()
            if 'folder' in j:
                j['type'] = 'folder'
            else:
                j['type'] = 'file'
            return j
        elif response.status_code == 404:
            return None
        else:
            raise SpoGraphGenericException("Failed to get path info", response)
        
    def folderExists(self, path: str = ""):
        pi = self.getPathInfo(path)
        if pi is None:
            return False
        if 'folder' in pi:
            return True
        else:
            return False
    def fileExists(self, path: str = ""):
        pi = self.getPathInfo(path)
        if pi is None:
            return False
        if 'folder' in pi:
            return False
        else:
            return True
    def pathExists(self, path: str = ""):
        return self.getPathInfo(path) is not None

    def listPath(self, path: str = ""):
        if os.path.dirname(self.getCombinedPath(path)) != '':
            graphUrl = 'https://graph.microsoft.com/v1.0/drives/' + urllib.parse.quote_plus(self._driveId) + '/root:/' + urllib.parse.quote_plus(self.getCombinedPath(path)) + ':/children'
        else:
            graphUrl = 'https://graph.microsoft.com/v1.0/drives/' + urllib.parse.quote_plus(self._driveId) + '/root/children'
        response = requests.get(
            graphUrl,
            headers={
                'Authorization': 'Bearer ' + str(self._token.getToken())
            }
        )
        if response.status_code == 404:
            raise SpoGraphNotFoundException("Failed to list path items for " + self.getCombinedPath(path), response)
        elif response.status_code != 200:
            raise SpoGraphGenericException("Failed to list path items for " + self.getCombinedPath(path), response)
        try:
            j = response.json()
            if 'value' in j:
                j = j['value']
                for el in j:
                    if 'folder' in el:
                        el['type'] = 'folder'
                    else:
                        el['type'] = 'file'
            else:
                raise SpoGraphException("Missing value key in response")
        except Exception as e:
            raise SpoGraphGenericException("Failed to list path items: " + str(e), response)
        return j

    def createFolder(self, path: str, ignoreIfFolderExists: bool = False):
        if os.path.dirname(self.getCombinedPath(path)) != '':
            graphUrl = 'https://graph.microsoft.com/v1.0/drives/' + urllib.parse.quote_plus(self._driveId) + '/root:/' + urllib.parse.quote_plus(os.path.dirname(self.getCombinedPath(path))) + ':/children'
        else:
            graphUrl = 'https://graph.microsoft.com/v1.0/drives/' + urllib.parse.quote_plus(self._driveId) + '/root/children'
        response = requests.post(
            graphUrl,
            headers={
                'Authorization': 'Bearer ' + str(self._token.getToken()),
                'Content-Type': 'application/json'
            },
            data=json.dumps({
                'name': os.path.basename(path),
                'folder': {}
            })
        )
        if response.status_code == 409:
            if ignoreIfFolderExists:
                j = self.getPathInfo(path)
                if 'folder' in j:
                    return j
            raise SpoGraphConflictException("Failed to create folder", response)
        elif response.status_code != 201:
            raise SpoGraphGenericException("Failed to create folder", response)
        return response.json()

    def uploadFile(self, path: str, localPath : str, contentType : str = ""):
        if contentType == "":
            mime = MimeTypes()
            contentType = mime.guess_type(os.path.basename(localPath))[0]
        return self.uploadFileContent(path, open(localPath, 'rb'), contentType)
    def uploadFileContent(self, path: str, data : io.BytesIO | io.StringIO | io.FileIO, contentType : str = ""):
        if contentType == "":
            raise SpoGraphException("Content-Type is required")
        response = requests.put(
            'https://graph.microsoft.com/v1.0/drives/' + urllib.parse.quote_plus(self._driveId) + '/root:/' + urllib.parse.quote_plus(self.getCombinedPath(path)) + ':/content',
            headers={
                'Authorization': 'Bearer ' + str(self._token.getToken()),
                'Content-Type': 'application/octet-stream'
            },
            data=data
        )
        if response.status_code == 409:
            raise SpoGraphConflictException("Failed to upload file", response)
        elif response.status_code == 404:
            raise SpoGraphNotFoundException("Failed to upload file", response)
        elif response.status_code != 201 and response.status_code != 200:
            raise SpoGraphGenericException("Failed to upload file", response)
        return response.json()

    def downloadFile(self, path: str, localPath : str):
        with open(localPath, 'wb') as f:
            f.write(self.downloadFileContent(path))
        return self
    def downloadFileContent(self, path: str):
        response = requests.get(
            'https://graph.microsoft.com/v1.0/drives/' + urllib.parse.quote_plus(self._driveId) + '/root:/' + urllib.parse.quote_plus(self.getCombinedPath(path)) + ':/content',
            headers={
                'Authorization': 'Bearer ' + str(self._token.getToken())
            }
        )
        if response.status_code == 404:
            raise SpoGraphNotFoundException("Failed to download file", response)
        elif response.status_code != 200:
            raise SpoGraphGenericException("Failed to download file", response)
        return response.content

    def deletePath(self, path: str) -> bool:
        response = requests.delete(
            'https://graph.microsoft.com/v1.0/drives/' + urllib.parse.quote_plus(self._driveId) + '/root:/' + urllib.parse.quote_plus(self.getCombinedPath(path)),
            headers={
                'Authorization': 'Bearer ' + str(self._token.getToken())
            }
        )
        if response.status_code == 404:
            return False
        elif response.status_code == 409:
            raise SpoGraphConflictException("Failed to delete path", response)
        elif response.status_code != 204:
            raise SpoGraphGenericException("Failed to delete path", response)
        return True



if args.spo_drivename == '':
    args.spo_drivename = 'Documents'


# creating the Sharepoint Online API object
if args.spo_use_default_credentials:
    spo = SpoGraphFileApi(
        SpoChainedTokenCredentialOauthProvider(DefaultAzureCredential()),
        args.spo_site,
        args.spo_drivename,
        args.spo_subpath
    )
else:
    if args.spo_tenant_id == '' or args.spo_client_id == '' or args.spo_client_secret == '':
        raise ValueError("Missing Sharepoint Online credentials")
    spo = SpoGraphFileApi(
        SpoClientSecretOauthProvider(args.spo_tenant_id, args.spo_client_id, args.spo_client_secret, False),
        args.spo_site,
        args.spo_drivename,
        args.spo_subpath
    )



print("")
print("Listing all drives:")
print(spo.listAllDriveNames())
print("")

if not spo.pathExists('spo-access-test'):
    print("Creating spo-access-test folder")
    spo.createFolder('spo-access-test')
else:
    print("spo-access-test folder already exists")
print("")

print("Uploading README.md")
spo.uploadFile('spo-access-test/README.md', 'README.md')
print("")

print("Listing spo-access-test folder")
print(spo.listPath('spo-access-test'))
print("")

print("Downloading README.md")
spo.downloadFile('spo-access-test/README.md', 'README.md.downloaded')
print("")

print("Reading README.md.downloaded")
with open('README.md.downloaded', 'r') as f:
    print("Read " + str(len(f.read())) + " bytes")
print("")

print("Deleting README.md.downloaded")
os.remove('README.md.downloaded')
print("")

print("Deleting README.md")
spo.deletePath('spo-access-test/README.md')
print("")

print("Listing spo-access-test folder")
print(spo.listPath('spo-access-test'))
print("")




