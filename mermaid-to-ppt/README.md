# The requirements and traditional approach

```pwsh
# install mermaid-cli and generate diagram
npm install -g @mermaid-js/mermaid-cli
```

```pwsh
mmdc -i diagram.mmd -o output.svg
```


## Best approach for PowerPoint

If you want to style elements in PowerPoint, use an **editable SVG** workflow.

```pwsh
# generate PowerPoint-editable SVG (recommended for styling in PPT)
.\generate-mermaid-ppt-svg.ps1 -InputMmd diagram.mmd -OutputSvg output-ppt-editable.svg
```

Defaults are now **dynamic** when you omit `-TargetWidthPx` and `-FontSizePx`:
- Width is auto-picked from diagram size (`1366`, `1600`, or `1920`)
- Font is auto-scaled and clamped to `6..12` (larger diagrams get smaller text)

If text becomes too large after **Convert to Shape**, generate with smaller base typography and a slide-friendly width:

```pwsh
.\generate-mermaid-ppt-svg.ps1 -InputMmd architecture.mmd -OutputSvg architecture-ppt-editable.svg
```

PowerPoint import steps:
1. In PowerPoint, use **Insert -> Pictures -> This Device**.
2. Select `output-ppt-editable.svg`.
3. In PowerPoint, right-click the SVG and choose **Convert to Shape** (then ungroup if needed).

Fallback (if your Office build still renders SVG text incorrectly):

```pwsh
# in case font size is an issue:
.\generate-mermaid-ppt-png.ps1 -InputMmd diagram.mmd -OutputPng output-ppt.png -FontSizePx <yourTargetFontSize>
# or also supply a target width:
.\generate-mermaid-ppt-png.ps1 -InputMmd diagram.mmd -OutputPng output-ppt.png -FontSizePx <yourTargetFontSize> -TargetWidthPx <yourTargetWidth>
```

