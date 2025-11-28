# ============================================================================
# GODOT MCP SERVER - INSTALACE PRO WINDOWS
# ============================================================================

Write-Host "=== Godot MCP Server Setup ===" -ForegroundColor Green

$projectPath = "C:\Users\Cowley\Documents\gemini-mcp-server"

# Vytvoření adresáře
if (-not (Test-Path $projectPath)) {
    New-Item -ItemType Directory -Path $projectPath | Out-Null
    Write-Host "✓ Adresář vytvořen" -ForegroundColor Green
}

Set-Location $projectPath

# Vytvoření venv
if (-not (Test-Path "venv")) {
    python -m venv venv
    Write-Host "✓ Virtuální prostředí vytvořeno" -ForegroundColor Green
}

# Aktivace a instalace
& "$projectPath\venv\Scripts\Activate.ps1"
python -m pip install --upgrade pip
pip install mcp

Write-Host "`n✓ Instalace dokončena!" -ForegroundColor Green
Write-Host "`nDalší krok: Spusťte .\register_gemini.ps1" -ForegroundColor Cyan