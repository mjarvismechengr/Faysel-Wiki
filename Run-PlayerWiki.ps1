param(
  [string]$SourceVault      = "C:\Users\mjarv\Documents\Personal\D&D\Faysel\Faysel Obsidian\Faysel Master",
  [string]$ScopeSubfolder   = "Campaign",
  [string]$WikiRoot         = "C:\Users\mjarv\Documents\Personal\D&D\Faysel\Other\webstuff\Faysel-Wiki"
)

$ErrorActionPreference = "Stop"

$exporter = Join-Path (Split-Path -Parent $PSCommandPath) "Export-PlayerWiki.ps1"
if (-not (Test-Path -LiteralPath $exporter)) {
  throw "Exporter not found next to this wrapper: $exporter"
}

$QuartzContentOut = Join-Path $WikiRoot "content"

Write-Host "== Exporting player wiki ==" -ForegroundColor Cyan
& $exporter -SourceVault $SourceVault -QuartzContentOut $QuartzContentOut -ScopeSubfolder $ScopeSubfolder

Write-Host "== Starting Quartz dev server ==" -ForegroundColor Cyan
Push-Location $WikiRoot
try {
  # ensure deps are installed
  if (-not (Test-Path -LiteralPath (Join-Path $WikiRoot "node_modules"))) {
    Write-Host "node_modules not found; running npm install..." -ForegroundColor Yellow
    npm install
  }
  npx quartz build --serve
} finally {
  Pop-Location
}
