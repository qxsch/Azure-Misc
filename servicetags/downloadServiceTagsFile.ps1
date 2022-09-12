$wr = Invoke-WebRequest "https://www.microsoft.com/en-us/download/confirmation.aspx?id=56519"

$links = $wr.Links | Where-Object { $_.href -like "*ServiceTags_*.json" } | Select-Object href
if($links.Count -gt 0) {
    Write-Host ( "Link is: " + $links[0].href)
    $parts = $links[0].href -split "/"
    $name = $parts[$parts.Count - 1]
    Write-Host ( "Downloading file to: $name" )
    Invoke-WebRequest $links[0].href -OutFile $name
}
else {
    Write-Host "Failed to locate link"
}
