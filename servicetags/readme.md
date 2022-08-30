# Find service tags for an IP

There are to scripts, that can be used.

## cidrmatchAz.ps1

This script fetches the information from ``Get-AzNetworkServiceTag``. \
This way you always get the live information.

The syntax looks like this:
```pwsh
.\cidrmatchAz.ps1 -ip "51.107.0.91"
```

## cidrmatchFile.ps1

This script fetches the information from the json file, that you can download at https://www.microsoft.com/en-us/download/details.aspx?id=56519 \
This way you can query faster and also from historical files.

The syntax looks like this:
```pwsh
.\cidrmatchAz.ps1 -ip "51.107.0.91" -jsonFile ".\ServiceTags_Public_20220822.json"
```
