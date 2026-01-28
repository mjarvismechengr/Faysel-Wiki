param(
  [string]$SourceVault    = "C:\Users\mjarv\Documents\Personal\D&D\Faysel\Faysel Obsidian\Faysel Master",
  [string]$ScopeSubfolder = "Campaign",
  [string]$WikiRoot       = "C:\Users\mjarv\Documents\Personal\D&D\Faysel\Other\webstuff\Faysel-Wiki",

  # Modes
  [switch]$ValidateOnly,   # validate only (no export, no build, no serve)
  [switch]$Serve,          # serve locally (runs quartz build --serve)
  [switch]$NoBuild         # with -Serve: don't rebuild, just serve (if supported by your setup)
)

$ErrorActionPreference = "Stop"

$exporter = Join-Path (Split-Path -Parent $PSCommandPath) "Export-PlayerWiki.ps1"
if (-not (Test-Path -LiteralPath $exporter)) {
  throw "Exporter not found next to this wrapper: $exporter"
}

$QuartzContentOut = Join-Path $WikiRoot "content"

Write-Host "== Exporting player wiki ==" -ForegroundColor Cyan

if ($ValidateOnly) {
  & $exporter -SourceVault $SourceVault -QuartzContentOut $QuartzContentOut -ScopeSubfolder $ScopeSubfolder -ValidateOnly
  Write-Host "ValidateOnly complete; no export/build/serve." -ForegroundColor Yellow
  return
}

# Normal path: export
& $exporter -SourceVault $SourceVault -QuartzContentOut $QuartzContentOut -ScopeSubfolder $ScopeSubfolder

# Build/Serve
Push-Location $WikiRoot
try {
  # ensure deps are installed
  if (-not (Test-Path -LiteralPath (Join-Path $WikiRoot "node_modules"))) {
    Write-Host "node_modules not found; running npm install..." -ForegroundColor Yellow
    npm install
  }

  if ($Serve) {
    Write-Host "== Starting Quartz dev server ==" -ForegroundColor Cyan

    if ($NoBuild) {
      # Quartz doesn't always support "serve without build" depending on version,
      # but leaving this here as a convenience toggle. If it errors, just omit -NoBuild.
      npx quartz serve
    } else {
      npx quartz build --serve
    }
  } else {
    Write-Host "== Building Quartz (no server) ==" -ForegroundColor Cyan
    npx quartz build
  }
}
finally {
  Pop-Location
}
