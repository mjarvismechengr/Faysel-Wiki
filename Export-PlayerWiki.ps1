param(
  [Parameter(Mandatory=$true)]
  [string]$SourceVault,

  [Parameter(Mandatory=$true)]
  [string]$QuartzContentOut,

  # Optional: only export notes under this subfolder (e.g. "Campaign")
  [string]$ScopeSubfolder = ""

  [switch]$ValidateOnly = $false,
  [switch]$FailOnWarnings = $false
)

# ---------- Helpers: YAML frontmatter parsing (simple, robust enough for your use) ----------

function Get-FrontmatterBlock {
  param([string]$Text)
  if ($Text -match '(?s)\A---\s*\r?\n(.*?)\r?\n---\s*\r?\n') {
    return $Matches[1]
  }
  return $null
}

function Parse-Frontmatter {
  param([string]$Fm)

  $dict = @{}
  if (-not $Fm) { return $dict }

  $lines = $Fm -split "`r?`n"
  $i = 0
  while ($i -lt $lines.Count) {
    $line = $lines[$i]

    # key: value
    if ($line -match '^\s*([A-Za-z0-9_\-]+)\s*:\s*(.*)\s*$') {
      $key = $Matches[1]
      $val = $Matches[2]

      if ($val -eq "") {
        # Possibly a list
        $items = @()
        $j = $i + 1
        while ($j -lt $lines.Count -and $lines[$j] -match '^\s*-\s*(.*)\s*$') {
          $items += $Matches[1].Trim()
          $j++
        }
        if ($items.Count -gt 0) {
          $dict[$key] = $items
          $i = $j
          continue
        } else {
          $dict[$key] = ""
          $i++
          continue
        }
      } else {
        $dict[$key] = $val.Trim()
        $i++
        continue
      }
    }

    $i++
  }

  return $dict
}

function Normalize-Bool {
  param($Value)
  if ($null -eq $Value) { return $false }
  $s = "$Value".Trim().ToLower()
  return ($s -eq "true" -or $s -eq "yes" -or $s -eq "1")
}

# ---------- Content extraction / cleanup ----------

function Strip-ObsidianComments {
  param([string]$Text)
  # Remove %% ... %% blocks (multiline)
  return [regex]::Replace($Text, '(?s)%%.*?%%', '')
}

function Extract-PlayerBlocks {
  param([string]$Text)

  # Matches :::player ... ::: (multiline)
  $matches = [regex]::Matches($Text, '(?s):::player\s*(.*?)\s*:::', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

  if ($matches.Count -eq 0) { return $null }

  $parts = @()
  foreach ($m in $matches) {
    $parts += $m.Groups[1].Value.Trim()
  }
  return ($parts -join "`n`n---`n`n")
}

# ---------- Infobox generation (Type-aware, but schema-agnostic) ----------

function Humanize-Key {
  param(
    [Parameter(Mandatory)]
    [string]$k
  )

  if (-not $k) { return "" }

  $s = $k.ToLowerInvariant()

  # Replace underscores and dashes with spaces
  $s = $s -replace '[_\-]+', ' '

  # Add space before digits (party1relation -> party 1 relation)
  $s = $s -replace '(\D)(\d+)', '$1 $2'

  # Normalize whitespace
  $s = ($s -replace '\s+', ' ').Trim()

  # Title Case
  return ([cultureinfo]::InvariantCulture.TextInfo.ToTitleCase($s))
}

function Value-To-Markdown {
  param($Value)

  if ($Value -is [System.Array]) {
    $vals = $Value | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
    return ($vals -join ", ")
  }
  return "$Value"
}

function Is-Linkish {
  param($Value)
  if ($Value -is [System.Array]) {
    foreach ($v in $Value) {
      if ("$v" -match '\[\[.*?\]\]') { return $true }
    }
    return $false
  }
  return ("$Value" -match '\[\[.*?\]\]')
}

function Group-FrontmatterNpc {
  param([hashtable]$fm)

  # Exclusions: internal / noisy / DM-only
  $excludeExact = @("tags","statblock","art1","starred")
  $excludePrefix = @("dm_","_")

  $bioPattern = '(?i)^(aliases|pronounced|ancestry|heritage|race|species|gender|pronouns|age|height|build|sexuality|alignment)$'
  $statusPattern = '(?i)^(condition|status|party\d+relation|last_seen_session|last_updated_session|current_status)$'
  $connectionsPattern = '(?i)^(location|ownedlocation|organization|religion|occupation|whichparty|faction|home|region)$'

  $groups = @{
    "Bio" = @{}
    "Status" = @{}
    "Connections" = @{}
    "Other" = @{}
  }

  foreach ($key in $fm.Keys) {
    $k = "$key"
    $val = $fm[$key]

    if ($excludeExact -contains $k) { continue }
    foreach ($p in $excludePrefix) { if ($k.StartsWith($p)) { continue 2 } }

    # skip empty
    if ($val -is [System.Array]) {
      if (($val | Where-Object { "$_".Trim() -ne "" }).Count -eq 0) { continue }
    } else {
      if ("$val".Trim() -eq "") { continue }
    }

    # Don't show export gate keys
    if ($k -ieq "player_visible" -or $k -ieq "type") { continue }

    # Grouping rules
    if ($k -match $bioPattern) {
      $groups["Bio"][$k] = $val; continue
    }
    if ($k -match $statusPattern) {
      $groups["Status"][$k] = $val; continue
    }
    if ($k -match $connectionsPattern -or (Is-Linkish -Value $val)) {
      $groups["Connections"][$k] = $val; continue
    }

    $groups["Other"][$k] = $val
  }

  return $groups
}

# ---------- Index settings ----------
$MakeFolderIndexes = $true
$MakeTypeIndexes   = $true   # set to $false if you only want folder landing pages
$IndexFolderName   = "_Indexes"  # where per-type pages live
$IndexTitle        = "Faysel Player Wiki"

$FrontmatterBlacklist = @(
  "player_visible",
  "type",
  "tags",
  "statblock",
  "art",
  "art1",
  "starred"
)

# ---------- Allowlists (per type) ----------

function Normalize-Key {
  param([string]$k)
  if (-not $k) { return "" }
  # lower, remove everything except letters/numbers
  return (($k.ToLowerInvariant() -replace '[^a-z0-9]+', ''))
}

# Build allowlists using human-friendly labels; we normalize both sides.
$TypeAllowRaw = @{
  "npc" = @(
    "Pronounced","Aliases","Ancestry","Heritage","Creature Type","Creature Sub-Type",
    "Gender","Age","Height","Build",
    "Languages","Occupations","Organizations","Religions",
    "Owned Locations","Current Location","Condition"
  )

  # Calendar-ish
  "calendar" = @("Aliases","Calendar Link")
  "year"     = @("Aliases","Era","Calendar Link")
  "month"    = @("Aliases","Season","Calendar Link")
  "event"    = @("Aliases","Category","Type","Start Date","End Date","Month of Occurrence","Year of Occurrence","Location","Minigames","Calendar Link")

  # Story / tracking
  "session"  = @("Aliases","Session Date","Character","Locations","Miscellaneous")
  "service"  = @("Aliases","Provider","Customer","Request Date","Estimated Delivery Date","Cost","Status")
  "quest"    = @("Aliases","Adventure","Status")
  "adventure"= @("Status")
  "rumor"    = @("Subject","Origin","Accuracy","Status")

  # People / orgs
  "organization" = @("Pronounced","Aliases","Hierarchy","Head","Steward","Parent Organization","Worship","HQ","Operating Areas")
  "player"       = @("Played By","Character Sheet","Pronounced","Aliases","Ancestry","Heritage","Gender","Age","Height","Weight","Occupations","Organizations","Religions","Owned Locations","Condition")
  "deity"        = @("Pronounced","Aliases","Domain","Power","Organizations","Owned Locations","Current Location","Condition")

  # Locations
  "poi"       = @("Pronounced","Aliases","Type","Dominion","Owners","Assistant","Organization","Location","Music")
  "district"  = @("Pronounced","Aliases","Type","Organizations","Location")
  "settlement"= @("Pronounced","Aliases","Type","Terrain","Owners","Defences","Location","Dominion","Rulers","Leaders","Organizations","Government Type","Population","Imports","Exports")
  "county"    = @("Pronounced","Aliases","Terrain","Dominion","Organizations","Location")
  "geography" = @("Pronounced","Aliases","Terrain","Dominion","Organizations","Location")
  "area"      = @("Pronounced","Aliases","Terrain","Dominion","Organizations","Location")
  "ocean"     = @("Pronounced","Aliases","Terrain","Dominion","Organizations","Location")
  "plane"     = @("Pronounced","Aliases","Terrain","Dominion","Organizations","Location")
  "planet"    = @("Pronounced","Aliases","Terrain","Dominion","Organizations","Location")

  # Items
  "letter"     = @("Aliases","Holder","Letter Sender","Sent From Location","Recipient of Letter","Sent to Location","Cost","Sent Date","Estimated Delivery Date","Previous Letter","Next Letter","Letter Status")
  "literature" = @("Aliases","Writers","Owner","Languages","Cost")
  "magicitem"  = @("Aliases","Owner","Previous Owners","Creators","Cost")
  "vehicle"    = @("Aliases","Owner","Previous Owners","Creators","Type","Captain/Commander","Cost","Speed","Required Crew","Crew Capacity","Cargo Capacity")
  "material"   = @("Locations","Cost")

  # Games
  "minigame" = @("Type","Players","Prestige","Events")

  # empty / later
  "hierarchy" = @()
}

# Normalize allowlists once for fast lookups
$TypeAllow = @{}
foreach ($t in $TypeAllowRaw.Keys) {
  $TypeAllow[$t] = @{}
  foreach ($k in $TypeAllowRaw[$t]) {
    $nk = Normalize-Key $k
    if ($nk -ne "") { $TypeAllow[$t][$nk] = $true }
  }
}

function Is-AllowedField {
  param(
    [string]$Type,
    [string]$Key
  )

  if (-not $Type) { return $true } # if type missing, don't block
  $t = $Type.Trim().ToLowerInvariant()
  if (-not $TypeAllow.ContainsKey($t)) { return $true } # unknown type, don't block

  # If allowlist is empty, allow nothing (except blacklisted handled elsewhere)
  if ($TypeAllow[$t].Count -eq 0) { return $false }

  $nk = Normalize-Key $Key
  return $TypeAllow[$t].ContainsKey($nk)
}

function Build-InfoboxMarkdown {
  param(
    [string]$Title,
    [hashtable]$fm
  )

  $type = "$($fm['type'])".Trim().ToLower()
  if ($type -eq "") { $type = "npc" }

  $art = $fm["art"]

  $groups =
    if ($type -eq "npc") { Group-FrontmatterNpc -fm $fm }
    else { Group-FrontmatterNpc -fm $fm }

  $lines = New-Object System.Collections.Generic.List[string]

  # Wrapper
  $lines.Add('<div class="infobox">')

  # Title
  if ($Title) {
    $safeTitle = $Title.Trim()
    if ($safeTitle) {
      $lines.Add("<div class=""infobox-title"">$safeTitle</div>")
    }
  }

   # Image
  if ($art -and "$art".Trim() -ne "") {
    $imgRel = "$art".Trim().Trim('"').TrimStart('/','\') -replace '\\','/'
    $alt = if ($Title) { $Title.Trim() } else { "Image" }
    $lines.Add("<img class=""infobox-image"" src=""/$imgRel"" alt=""$alt"">")
  }

  # Start table
  $lines.Add('')
  $lines.Add('|  |  |')
  $lines.Add('|---|---|')

  foreach ($gName in @("Bio","Status","Connections","Other")) {
    $g = $groups[$gName]
    if (-not $g -or $g.Count -eq 0) { continue }

    # Group header row
    $lines.Add("| **$gName** |  |")

    foreach ($k in ($g.Keys | Sort-Object)) {
      if ($FrontmatterBlacklist -contains $k) { continue }
      if (-not (Is-AllowedField -Type $type -Key $k)) { continue }

      $label = Humanize-Key ([string]$k)
      $valMd = Value-To-Markdown $g[$k]

      if ($valMd -and $valMd.Trim()) {
        $lines.Add("| **$label** | $valMd |")
      }
    }
  }

  # End wrapper
  $lines.Add('')
  $lines.Add('</div>')
  $lines.Add('')

  return ($lines -join "`n")
}

# ---------- Asset copying ----------

function Copy-AssetIfExists {
  param(
    [string]$SourceVault,
    [string]$QuartzContentOut,
    [string]$AssetPath
  )

  if (-not $AssetPath) { return }

  $assetRel = $AssetPath.Trim().Trim('"').TrimStart('/','\')
  $sourceAbs = Join-Path $SourceVault $assetRel

  if (Test-Path $sourceAbs) {
    $destAbs = Join-Path $QuartzContentOut $assetRel
    $destDir = Split-Path $destAbs -Parent
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    Copy-Item -Force -LiteralPath $sourceAbs -Destination $destAbs
  }
}

function Copy-EmbeddedAssetsFromText {
  param(
    [string]$SourceVault,
    [string]$QuartzContentOut,
    [string]$Text
  )

  if (-not $Text) { return }

  # 1) Obsidian embeds: ![[path]] or ![[path|alias]]
  $m = [regex]::Matches($Text, '!\[\[([^\]]+?)\]\]')
  foreach ($x in $m) {
    $p = $x.Groups[1].Value
    if ($p -match '^(.*?)\|') { $p = $Matches[1] }
    Copy-AssetIfExists -SourceVault $SourceVault -QuartzContentOut $QuartzContentOut -AssetPath $p
  }

  # 2) Markdown images: ![alt](path)  (handles /path, ./path, relative paths)
  $m2 = [regex]::Matches($Text, '!\[[^\]]*\]\(([^)]+)\)')
  foreach ($x in $m2) {
    $p = $x.Groups[1].Value.Trim().Trim('"').Trim("'")

    # strip optional title: ![](path "title")
    if ($p -match '^(.+?)\s+["'']') { $p = $Matches[1] }

    # ignore external URLs and data URIs
    if ($p -match '^(https?:)?//') { continue }
    if ($p -match '^data:') { continue }

    # if we used absolute "/z_Assets/..", convert to vault-relative "z_Assets/.."
    if ($p.StartsWith('/')) { $p = $p.Substring(1) }

    Copy-AssetIfExists -SourceVault $SourceVault -QuartzContentOut $QuartzContentOut -AssetPath $p
  }

  # 3) Optional: HTML <img src="...">
  $m3 = [regex]::Matches($Text, '<img[^>]+src=["'']([^"''>]+)["'']', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  foreach ($x in $m3) {
    $p = $x.Groups[1].Value.Trim()

    if ($p -match '^(https?:)?//') { continue }
    if ($p -match '^data:') { continue }

    if ($p.StartsWith('/')) { $p = $p.Substring(1) }

    Copy-AssetIfExists -SourceVault $SourceVault -QuartzContentOut $QuartzContentOut -AssetPath $p
  }
}

function To-Slug {
  param([string]$s)
  if (-not $s) { return "" }
  $t = $s.Trim()
  # Quartz uses hyphens for spaces in URLs
  $t = $t -replace '\s+', '-'
  return $t
}

function Normalize-Text {
  param([string]$t)
  if ($null -eq $t) { return $t }

  # NBSP -> normal space
  $t = $t -replace [char]0x00A0, ' '

  # Fix common mojibake caused by UTF-8 text being interpreted as Windows-1252.
  # We only attempt this conversion when we see telltale characters to avoid mangling normal text.
  if ($t -match "[\u00C2\u00C3\u00E2]") {
    try {
      $enc1252 = [System.Text.Encoding]::GetEncoding(1252)
      $bytes   = $enc1252.GetBytes($t)
      $t2      = [System.Text.Encoding]::UTF8.GetString($bytes)

      # Accept the converted text only if it looks "less mojibake-y"
      $badBefore = ([regex]::Matches($t, "[\u00C2\u00C3\u00E2]").Count)
      $badAfter  = ([regex]::Matches($t2, "[\u00C2\u00C3\u00E2]").Count)

      if ($badAfter -lt $badBefore) { $t = $t2 }
    } catch {
      # If conversion fails, keep original text
    }
  }

  return $t
}


function Write-MarkdownFile {
  param(
    [Parameter(Mandatory)] [string]$Path,
    [Parameter()] [object]$Lines
  )

  $dir = Split-Path $Path -Parent
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

  # Coerce into a single string safely
  if ($null -eq $Lines) {
    $text = ""
  } elseif ($Lines -is [string]) {
    $text = $Lines
  } else {
    $text = ($Lines -join "`n")
  }

  $text = Normalize-Text $text
  Set-Content -LiteralPath $Path -Value $text -Encoding UTF8
}


function Build-LinkLine {
  param(
    [Parameter(Mandatory)] [string]$RelPathFromContent  # e.g. "NPCs/Test NPC.md"
  )
  $name = [IO.Path]::GetFileNameWithoutExtension($RelPathFromContent)
  $folder = Split-Path $RelPathFromContent -Parent
  if ($folder -and $folder -ne ".") {
    return "- [[${folder}/${name}|${name}]]"
  }
  return "- [[${name}]]"
}

# ---------- Main export ----------

$root = $SourceVault
if ($ScopeSubfolder -ne "") {
  $root = Join-Path $SourceVault $ScopeSubfolder
}

New-Item -ItemType Directory -Force -Path $QuartzContentOut | Out-Null

# Wipe previous export so removed notes disappear from the player site
Get-ChildItem -Path $QuartzContentOut -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch '\\\.git\\' } |
  Remove-Item -Force

$files = Get-ChildItem -Path $root -Recurse -Filter *.md -File

# Track what we exported so we can build indexes at the end
$ExportedRelPaths = New-Object System.Collections.Generic.List[string]
$ExportedByType   = @{}   # type -> list of relpaths

$Warnings = New-Object System.Collections.Generic.List[string]
$Scanned = 0
$WouldExport = 0

foreach ($f in $files) {
  $raw = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
  $raw = Strip-ObsidianComments $raw

  $Scanned++

  $fmBlock = Get-FrontmatterBlock $raw
  $fm = Parse-Frontmatter $fmBlock

  $playerText = Extract-PlayerBlocks $raw
  $hasPlayerBlock = [bool]$playerText

  $pv = Normalize-Bool $fm["player_visible"]

  # Warnings for common footguns
  if ($pv -and -not $hasPlayerBlock) {
  $Warnings.Add("SKIP: player_visible=true but no :::player block -> $($f.FullName)") | Out-Null
  continue
  }

  if (-not $pv -and $hasPlayerBlock) {
  $Warnings.Add("SKIP: has :::player block but player_visible!=true -> $($f.FullName)") | Out-Null
  continue
  }

  if (-not $pv) { continue }          # must be explicit opt-in
  if (-not $hasPlayerBlock) { continue }  # must have player block for safety

  if (-not $fm.ContainsKey("type") -or [string]::IsNullOrWhiteSpace($fm["type"])) {
  $Warnings.Add("WARN: missing type in frontmatter -> $($f.FullName)") | Out-Null
  }

  $title = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
  $infobox = Build-InfoboxMarkdown -Title $title -fm $fm

  # Copy frontmatter art + any embeds inside player text
  Copy-AssetIfExists -SourceVault $SourceVault -QuartzContentOut $QuartzContentOut -AssetPath $fm["art"]
  Copy-EmbeddedAssetsFromText -SourceVault $SourceVault -QuartzContentOut $QuartzContentOut -Text $playerText

  # Preserve relative structure from scope root
  $relative = $f.FullName.Substring($root.Length).TrimStart('\','/')
  $relNorm = $relative -replace '\\','/'   # Quartz-friendly
  $ExportedRelPaths.Add($relNorm) | Out-Null
  $WouldExport++

  if ($ValidateOnly) {
  continue
  }

  $destPath = Join-Path $QuartzContentOut $relative
  $destDir  = Split-Path $destPath -Parent
  New-Item -ItemType Directory -Force -Path $destDir | Out-Null

  $out = @()
  $out += "---"
  $out += "type: $($fm['type'])"
  $out += "---"
  $out += ""
  $out += $infobox
  $out += ""
  $out += $playerText.Trim()
  $out += ""

  Write-MarkdownFile -Path $destPath -Lines ($out -join "`n")
}

# Ensure home page exists (Quartz needs content/index.md)
$indexPath = Join-Path $QuartzContentOut "index.md"
$index = @(
  "---"
  "title: Faysel Player Wiki"
  "---"
  ""
  "# Faysel Player Wiki"
  ""
  "Use search, or browse by folders."
)

Write-MarkdownFile -Path $indexPath -Lines ($index -join "`n")

# ---------- Build index pages ----------
if ($MakeFolderIndexes -or $MakeTypeIndexes) {

  # 1) HOME index.md
  if ($true) {
    $topFolders = $ExportedRelPaths |
      ForEach-Object {
        $p = $_
        if ($p -match '^([^/]+)/') { $Matches[1] } else { "" }
      } |
      Where-Object { $_ -ne "" -and $_ -ne $IndexFolderName } |
      Sort-Object -Unique

    $lines = @()
    $lines += "---"
    $lines += "title: $IndexTitle"
    $lines += "---"
    $lines += ""
    $lines += "# $IndexTitle"
    $lines += ""
    $lines += "## Browse"
    foreach ($f in $topFolders) {
      $lines += "- [[${f}/index|${f}]]"
    }

    if ($MakeTypeIndexes -and $ExportedByType.Keys.Count -gt 0) {
      $lines += ""
      $lines += "## Indexes"
      $lines += "- [[${IndexFolderName}/index|All Indexes]]"
    }

    Write-MarkdownFile -Path (Join-Path $QuartzContentOut "index.md") -Lines $lines
  }

  # 2) Folder landing pages: <folder>/index.md
  if ($MakeFolderIndexes) {
    $idxEsc = [regex]::Escape($IndexFolderName)
    $allFolders = $ExportedRelPaths |
      ForEach-Object {
        $p = $_
        $dir = Split-Path $p -Parent
        if ($dir -and $dir -ne ".") { ($dir -replace '\\','/') } else { "" }
      } |
      Where-Object { $_ -ne "" -and $_ -notmatch ("^" + $idxEsc + "(/|$)") } |
      Sort-Object -Unique

    foreach ($folder in $allFolders) {
      # pages directly in this folder (not in subfolders)
      $pages = $ExportedRelPaths |
        Where-Object {
          ((Split-Path $_ -Parent) -replace '\\','/') -eq $folder -and ($_ -notmatch '/index\.md$')
        } |
        Sort-Object

      $title = $folder.Split('/')[-1]
      $lines = @()
      $lines += "---"
      $lines += "title: $title"
      $lines += "---"
      $lines += ""
      $lines += "# $title"
      $lines += ""

      if ($pages.Count -eq 0) {
        $lines += "_No pages yet._"
      } else {
        foreach ($p in $pages) { $lines += (Build-LinkLine -RelPathFromContent $p) }
      }

      Write-MarkdownFile -Path (Join-Path $QuartzContentOut ($folder + "/index.md")) -Lines $lines
    }
  }

  # 3) Type indexes: _Indexes/<type>.md and _Indexes/index.md
  if ($MakeTypeIndexes) {
    $indexRoot = Join-Path $QuartzContentOut $IndexFolderName
    if (-not (Test-Path $indexRoot)) { New-Item -ItemType Directory -Force -Path $indexRoot | Out-Null }

    # Master index
    $master = @()
    $master += "---"
    $master += "title: Indexes"
    $master += "---"
    $master += ""
    $master += "# Indexes"
    $master += ""

    foreach ($t in ($ExportedByType.Keys | Sort-Object)) {
      $master += "- [[${IndexFolderName}/${t}|$t]]"

      $paths = $ExportedByType[$t] | Sort-Object
      $lines = @()
      $lines += "---"
      $lines += "title: $t"
      $lines += "---"
      $lines += ""
      $lines += "# $t"
      $lines += ""
      foreach ($p in $paths) { $lines += (Build-LinkLine -RelPathFromContent $p) }

      Write-MarkdownFile -Path (Join-Path $indexRoot ($t + ".md")) -Lines $lines
    }

    Write-MarkdownFile -Path (Join-Path $indexRoot "index.md") -Lines $master
  }
}

Write-Host ""
Write-Host "Validation summary:"
Write-Host "  Scanned:      $Scanned"
Write-Host "  Would export: $WouldExport"
Write-Host "  Warnings:     $($Warnings.Count)"
if ($Warnings.Count -gt 0) {
  Write-Host ""
  Write-Host "Warnings:"
  $Warnings | ForEach-Object { Write-Host "  - $_" }
  if ($FailOnWarnings) { throw "FailOnWarnings enabled and warnings were found." }
}

Write-Host "Export complete: $(Get-Date)"
