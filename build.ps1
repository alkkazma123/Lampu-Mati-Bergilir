<#
.SYNOPSIS
    Build script untuk Lampu Mati Bergilir - Roblox Horror Game
.DESCRIPTION
    Script PowerShell untuk install Rojo (jika belum), build project,
    dan opsional menjalankan live-sync server.
.EXAMPLE
    .\build.ps1              # Build saja
    .\build.ps1 -Serve       # Jalankan Rojo serve (live-sync)
    .\build.ps1 -Install     # Install/update Rojo via Aftman
#>

param(
    [switch]$Serve,
    [switch]$Install,
    [switch]$Help
)

$ErrorActionPreference = "Stop"

# ─── Warna output ───
function Write-Step  { param($msg) Write-Host "  [*] $msg" -ForegroundColor Cyan }
function Write-OK    { param($msg) Write-Host "  [+] $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "  [!] $msg" -ForegroundColor Yellow }
function Write-Err   { param($msg) Write-Host "  [-] $msg" -ForegroundColor Red }

# ─── Banner ───
Write-Host ""
Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "  ║     LAMPU MATI BERGILIR - Build Tool     ║" -ForegroundColor Magenta
Write-Host "  ║        Roblox Horror Game Builder        ║" -ForegroundColor DarkMagenta
Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Magenta
Write-Host ""

if ($Help) {
    Write-Host "  Penggunaan:" -ForegroundColor White
    Write-Host "    .\build.ps1              Build file .rbxlx" -ForegroundColor Gray
    Write-Host "    .\build.ps1 -Serve       Jalankan Rojo live-sync server" -ForegroundColor Gray
    Write-Host "    .\build.ps1 -Install     Install Rojo via Aftman/Foreman" -ForegroundColor Gray
    Write-Host "    .\build.ps1 -Help        Tampilkan bantuan ini" -ForegroundColor Gray
    Write-Host ""
    exit 0
}

# ─── Cek lokasi project ───
$projectFile = Join-Path $PSScriptRoot "default.project.json"
if (-not (Test-Path $projectFile)) {
    Write-Err "default.project.json tidak ditemukan di $PSScriptRoot"
    Write-Err "Pastikan menjalankan script dari root project."
    exit 1
}
Write-OK "Project file ditemukan: $projectFile"

# ─── Install Rojo jika diminta ───
if ($Install) {
    Write-Step "Memeriksa tool manager..."

    # Coba Aftman dulu, lalu Foreman
    $aftman  = Get-Command aftman  -ErrorAction SilentlyContinue
    $foreman = Get-Command foreman -ErrorAction SilentlyContinue

    if ($aftman) {
        Write-Step "Menggunakan Aftman untuk install Rojo..."
        & aftman install
    }
    elseif ($foreman) {
        Write-Step "Menggunakan Foreman untuk install Rojo..."
        & foreman install
    }
    else {
        Write-Warn "Aftman/Foreman tidak ditemukan. Mencoba install Rojo via cargo..."
        $cargo = Get-Command cargo -ErrorAction SilentlyContinue
        if ($cargo) {
            & cargo install rojo --locked
        }
        else {
            Write-Err "Tidak bisa install Rojo otomatis."
            Write-Err "Install manual: https://rojo.space/docs/v7/getting-started/installation/"
            exit 1
        }
    }
    Write-OK "Rojo terinstall!"
}

# ─── Cek Rojo tersedia ───
$rojo = Get-Command rojo -ErrorAction SilentlyContinue
if (-not $rojo) {
    Write-Err "Rojo tidak ditemukan di PATH!"
    Write-Err "Jalankan: .\build.ps1 -Install"
    Write-Err "Atau install manual: https://rojo.space/docs/v7/getting-started/installation/"
    exit 1
}

$rojoVersion = & rojo --version 2>$null
Write-OK "Rojo ditemukan: $rojoVersion"

# ─── Serve mode ───
if ($Serve) {
    Write-Step "Menjalankan Rojo live-sync server..."
    Write-Host ""
    Write-Host "  Buka Roblox Studio -> Plugins -> Rojo -> Connect" -ForegroundColor Yellow
    Write-Host "  Default: localhost:34872" -ForegroundColor Yellow
    Write-Host "  Tekan Ctrl+C untuk berhenti" -ForegroundColor Gray
    Write-Host ""
    & rojo serve $projectFile
    exit 0
}

# ─── Build mode (default) ───
$outputFile = Join-Path $PSScriptRoot "game.rbxlx"

Write-Step "Building project..."
Write-Step "Output: $outputFile"

& rojo build $projectFile -o $outputFile

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-OK "Build berhasil!"
    Write-OK "File: $outputFile"
    Write-Host ""
    Write-Host "  Langkah selanjutnya:" -ForegroundColor White
    Write-Host "    1. Buka file game.rbxlx di Roblox Studio" -ForegroundColor Gray
    Write-Host "    2. Atau jalankan: .\build.ps1 -Serve untuk live-sync" -ForegroundColor Gray
    Write-Host ""
}
else {
    Write-Err "Build gagal! Periksa error di atas."
    exit 1
}
