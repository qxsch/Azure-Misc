# The requirements and traditional approach

```pwsh
# install mermaid-cli and generate diagram
npm install -g @mermaid-js/mermaid-cli
```

```pwsh
mmdc -i diagram.mmd -o output.svg
```

## Best approach for outlook

```pwsh
# use png converts the diagram to a high-resolution PNG
# if you ommit `--use-png`, the diagram is embedded as an SVG, which may not render correctly in Outlook
.\build_html.py -i documentation.md -o documentation.html --use-png
```

Then open `documentation.html` in a web browser, press ``ctrl+a`` to select all, ``ctrl+c`` to copy the rendered diagram, and paste it into Outlook. This ensures the diagram is rendered correctly and can be styled as needed within the email.

