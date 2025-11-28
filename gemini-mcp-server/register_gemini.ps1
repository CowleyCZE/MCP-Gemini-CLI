# ============================================================================
# REGISTRACE GODOT MCP SERVERU V GEMINI CLI
# ============================================================================

Write-Host "=== Registrace Godot MCP serveru ===" -ForegroundColor Green

$pythonPath = "C:\Users\Cowley\Documents\gemini-mcp-server\venv\Scripts\python.exe"
$serverPath = "C:\Users\Cowley\Documents\gemini-mcp-server\godot_mcp_server.py"

# Kontrola Gemini CLI
try {
    $null = gemini --version 2>&1
    Write-Host "✓ Gemini CLI nalezeno" -ForegroundColor Green
} catch {
    Write-Host "✗ Gemini CLI není nainstalováno!" -ForegroundColor Red
    Write-Host "Instalace: npm install -g @google/generative-ai-cli" -ForegroundColor Yellow
    exit 1
}

# Odebrání starého serveru
Write-Host "Odstraňuji starý server..." -ForegroundColor Yellow
gemini mcp remove godot 2>$null

# Registrace nového serveru - OPRAVENO
Write-Host "Registruji nový server..." -ForegroundColor Green
gemini mcp add godot `
    --command "$pythonPath" `
    --args "$serverPath" `
    --timeout 15000

Write-Host "`n✓ Server zaregistrován!" -ForegroundColor Green

# Seznam serverů
Write-Host "`n=== Registrované servery ===" -ForegroundColor Green
gemini mcp list

Write-Host "`n
POUŽITÍ:

1. Spusťte Godot Editor s MCP Bridge pluginem
2. Spusťte: gemini
3. Zkontrolujte: /mcp
4. Zkuste: Vytvoř Node3D s názvem Player

" -ForegroundColor Cyan