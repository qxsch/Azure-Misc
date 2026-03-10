param(
    [Parameter(Mandatory = $false)]
    [string]$InputMmd = "diagram.mmd",

    [Parameter(Mandatory = $false)]
    [string]$OutputSvg = "output-ppt-editable.svg",

    [Parameter(Mandatory = $false)]
    [int]$TargetWidthPx = 0,

    [Parameter(Mandatory = $false)]
    [int]$FontSizePx = 0
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $InputMmd)) {
    throw "Input Mermaid file not found: $InputMmd"
}

$inputMmdPath = [System.IO.Path]::GetFullPath($InputMmd)
$outputSvgPath = [System.IO.Path]::GetFullPath($OutputSvg)
$mermaidConfigPath = Join-Path ([System.IO.Path]::GetDirectoryName($outputSvgPath)) "mermaid-ppt-editable-config.json"

$requestedTargetWidthPx = $TargetWidthPx
$requestedFontSizePx = $FontSizePx

if ($TargetWidthPx -le 0) {
    $TargetWidthPx = 1366
}

if ($FontSizePx -le 0) {
    $FontSizePx = 10
}

$mmdc = Get-Command mmdc -ErrorAction SilentlyContinue
if (-not $mmdc) {
    throw "mmdc not found. Install Mermaid CLI first: npm install -g @mermaid-js/mermaid-cli"
}

@'
{
  "htmlLabels": false,
    "useMaxWidth": false,
    "fontSize": __FONT_SIZE__,
    "themeVariables": {
        "fontSize": "__FONT_SIZE_PX__"
    },
  "flowchart": {
        "htmlLabels": false,
        "useMaxWidth": false
  },
    "themeCSS": "#my-svg{font-size:__FONT_SIZE_PX__ !important;} .edgeLabel,.edgeLabel p,.labelBkg,.edgeLabel rect,.icon-shape .label rect,.image-shape .label rect{background:transparent !important;fill:transparent !important;opacity:0 !important;stroke:none !important;}"
}
'@.Replace("__FONT_SIZE__", $FontSizePx.ToString()).Replace("__FONT_SIZE_PX__", ("{0}px" -f $FontSizePx)) | Set-Content -Path $mermaidConfigPath -Encoding UTF8

Write-Host "Generating PowerPoint-editable SVG from Mermaid file..."
try {
    & $mmdc.Source -i $inputMmdPath -o $outputSvgPath -c $mermaidConfigPath
}
finally {
    if (Test-Path $mermaidConfigPath) {
        Remove-Item $mermaidConfigPath -Force
    }
}

if (-not (Test-Path $outputSvgPath)) {
    throw "SVG generation failed. Expected file not found: $outputSvgPath"
}

$svgContent = Get-Content -Path $outputSvgPath -Raw
$viewBoxMatch = [regex]::Match($svgContent, 'viewBox\s*=\s*"([0-9\.\-]+)\s+([0-9\.\-]+)\s+([0-9\.\-]+)\s+([0-9\.\-]+)"')
if ($viewBoxMatch.Success) {
    $vbWidth = [double]$viewBoxMatch.Groups[3].Value
    $vbHeight = [double]$viewBoxMatch.Groups[4].Value

    if ($vbWidth -gt 0) {
        if ($requestedTargetWidthPx -le 0) {
            if ($vbWidth -ge 3600) {
                $TargetWidthPx = 1920
            }
            elseif ($vbWidth -ge 2400) {
                $TargetWidthPx = 1600
            }
            else {
                $TargetWidthPx = 1366
            }
        }

        if ($requestedFontSizePx -le 0) {
            $relativeScale = $TargetWidthPx / $vbWidth
            $autoFontSize = [math]::Round(12 * [math]::Pow($relativeScale, 0.65))
            if ($vbWidth -ge 5000) {
                $autoFontSize -= 2
            }
            elseif ($vbWidth -ge 3600) {
                $autoFontSize -= 1
            }
            if ($autoFontSize -lt 6) { $autoFontSize = 6 }
            if ($autoFontSize -gt 12) { $autoFontSize = 12 }
            $FontSizePx = [int]$autoFontSize
        }

        if ($requestedTargetWidthPx -le 0 -or $requestedFontSizePx -le 0) {
            @'
{
  "htmlLabels": false,
  "useMaxWidth": false,
  "fontSize": __FONT_SIZE__,
  "themeVariables": {
    "fontSize": "__FONT_SIZE_PX__"
  },
  "flowchart": {
    "htmlLabels": false,
    "useMaxWidth": false
  },
  "themeCSS": "#my-svg{font-size:__FONT_SIZE_PX__ !important;} .edgeLabel,.edgeLabel p,.labelBkg,.edgeLabel rect,.icon-shape .label rect,.image-shape .label rect{background:transparent !important;fill:transparent !important;opacity:0 !important;stroke:none !important;}"
}
'@.Replace("__FONT_SIZE__", $FontSizePx.ToString()).Replace("__FONT_SIZE_PX__", ("{0}px" -f $FontSizePx)) | Set-Content -Path $mermaidConfigPath -Encoding UTF8

            try {
                & $mmdc.Source -i $inputMmdPath -o $outputSvgPath -c $mermaidConfigPath
            }
            finally {
                if (Test-Path $mermaidConfigPath) {
                    Remove-Item $mermaidConfigPath -Force
                }
            }

            if (-not (Test-Path $outputSvgPath)) {
                throw "SVG generation failed after auto-tuning. Expected file not found: $outputSvgPath"
            }

            $svgContent = Get-Content -Path $outputSvgPath -Raw
            $viewBoxMatch = [regex]::Match($svgContent, 'viewBox\s*=\s*"([0-9\.\-]+)\s+([0-9\.\-]+)\s+([0-9\.\-]+)\s+([0-9\.\-]+)"')
            if ($viewBoxMatch.Success) {
                $vbWidth = [double]$viewBoxMatch.Groups[3].Value
                $vbHeight = [double]$viewBoxMatch.Groups[4].Value
            }
        }
    }

    if ($vbWidth -gt 0 -and $TargetWidthPx -gt 0) {
        $targetHeight = [math]::Round($vbHeight * ($TargetWidthPx / $vbWidth), 3)
        $svgTagRegex = [regex]::new('<svg\b[^>]*>')
        $svgContent = $svgTagRegex.Replace(
            $svgContent,
            [System.Text.RegularExpressions.MatchEvaluator]{
                param($m)
                $tag = $m.Value
                $tag = [regex]::Replace($tag, '\bwidth\s*=\s*"[^"]*"', ('width="{0}"' -f $TargetWidthPx))
                $tag = [regex]::Replace($tag, '\bheight\s*=\s*"[^"]*"', ('height="{0}"' -f $targetHeight))
                $tag = [regex]::Replace($tag, 'max-width\s*:\s*[^;\"]*;?', '', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                return $tag
            },
            1
        )
        Set-Content -Path $outputSvgPath -Value $svgContent -Encoding UTF8
    }
}

$foreignObjectCount = (Select-String -Path $outputSvgPath -Pattern 'foreignObject' -AllMatches | Measure-Object).Count
if ($foreignObjectCount -gt 0) {
    Write-Warning "SVG still contains $foreignObjectCount foreignObject element(s). PowerPoint may lose some text."
}

if ($requestedTargetWidthPx -le 0 -or $requestedFontSizePx -le 0) {
    Write-Host ("Auto-tuned values -> TargetWidthPx: {0}, FontSizePx: {1}" -f $TargetWidthPx, $FontSizePx)
}

Write-Host "Done. PPT-editable SVG generated: $outputSvgPath"