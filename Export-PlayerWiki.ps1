param(
  [Parameter(Mandatory=$true)]
  [string]$SourceVault,

  [Parameter(Mandatory=$true)]
  [string]$QuartzContentOut,

  [string]$ScopeSubfolder = "Campaign",

  # Run modes
  [switch]$ValidateOnly,

  # Index generation
  [switch]$MakeFolderIndexes,
  [switch]$MakeTypeIndexes,
  [string]$IndexFolderName = "_Indexes",
  [string]$IndexTitle      = "Faysel Player Wiki",

  # Output/behavior switches
  [switch]$FailOnWarnings,
  [switch]$ShowInfo,
  [bool]$WriteExportList  = $true,
  [bool]$CleanStaleContent = $true,
  [bool]$CleanOrphanAssets = $false
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


# ---------- Leaflet map extraction (Obsidian Leaflet plugin -> Quartz static assets) ----------

function Get-LeafletBlock {
  param([string]$Text)

  if (-not $Text) { return $null }
  $m = [regex]::Match($Text, '(?s)```leaflet\s*(.*?)\s*```', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  if (-not $m.Success) { return $null }
  return $m.Groups[1].Value
}

function Parse-LeafletAssets {
  param(
    [string]$LeafletBody
  )

  $result = [ordered]@{
    ImageRef     = $null
    GeoJsonRefs  = @()
    Bounds       = $null
    MinZoom      = $null
    MaxZoom      = $null
    DefaultZoom  = $null
    Lat          = $null
    Long         = $null
    Height       = $null
  }

  if (-not $LeafletBody) { return $result }

  $inGeoJson = $false

  foreach ($line in ($LeafletBody -split "`r?`n")) {
    $t = $line.Trim()

    if ($t -eq "") {
      # blank line ends geojson list block
      $inGeoJson = $false
      continue
    }

    if ($t -match '^(?i)image:\s*(.+)$') { $result.ImageRef = $Matches[1].Trim(); continue }
    if ($t -match '^(?i)bounds:\s*(.+)$') { $result.Bounds = $Matches[1].Trim(); continue }
    if ($t -match '^(?i)minZoom:\s*(.+)$') { $result.MinZoom = $Matches[1].Trim(); continue }
    if ($t -match '^(?i)maxZoom:\s*(.+)$') { $result.MaxZoom = $Matches[1].Trim(); continue }
    if ($t -match '^(?i)defaultZoom:\s*(.+)$') { $result.DefaultZoom = $Matches[1].Trim(); continue }
    if ($t -match '^(?i)lat:\s*(.+)$') { $result.Lat = $Matches[1].Trim(); continue }
    if ($t -match '^(?i)long:\s*(.+)$') { $result.Long = $Matches[1].Trim(); continue }
    if ($t -match '^(?i)height:\s*(.+)$') { $result.Height = $Matches[1].Trim(); continue }

    # Turn on "geojson mode"
    if ($t -match '^(?i)geojson:\s*$') {
      $inGeoJson = $true
      continue
    }

    # Only read list items while we're inside geojson:
    if ($inGeoJson -and ($t -match '^(?i)-\s*(\[\[.*?\]\])\s*$')) {
      $result.GeoJsonRefs += $Matches[1].Trim()
      continue
    }

    # Any other non-list line ends geojson mode
    if ($inGeoJson -and ($t -notmatch '^(?i)-\s*')) {
      $inGeoJson = $false
    }
  }

  return $result
}

function Build-MapSectionMarkdown {
  param(
    [string]$RawNoteText,
    [hashtable]$AssetIndex
  )

  $leaflet = Get-LeafletBlock -Text $RawNoteText
  if (-not $leaflet) { return $null }

  $a = Parse-LeafletAssets -LeafletBody $leaflet

  if (-not $a.ImageRef) { return $null }

  $imgRel = Resolve-AssetRelPath -AssetRef $a.ImageRef -AssetIndex $AssetIndex
  if (-not $imgRel) { return $null }

  # Bounds must exist for interactive map
  if (-not $a.Bounds) { return $null }

  # Normalize bounds text so it becomes valid JSON
  # Example: [[0,0], [1914.11, 1764.30]] -> [[0,0],[1914.11,1764.30]]
  $boundsJson = ($a.Bounds -replace '\s+', '') -replace '^\[', '['

  # GeoJSON URLs (resolved)
  $geoUrls = @()
  foreach ($gj in $a.GeoJsonRefs) {
    $gjRel = Resolve-AssetRelPath -AssetRef $gj -AssetIndex $AssetIndex
    if ($gjRel) { $geoUrls += "$gjRel" }
  }
  $geoJsonArray = ($geoUrls | ConvertTo-Json -Compress)

  # Height (optional)
  $heightCss = "600px"
  if ($a.Height -match '(\d+)') { $heightCss = "$($Matches[1])px" }

  # Build collapsible HTML
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("## Map")
  $lines.Add("")
  $lines.Add("<details open>")
  $lines.Add("<summary>Map</summary>")
  $lines.Add("")
  $lines.Add("<div class=`"leaflet-map`" style=`"height: $heightCss; margin-top: 0.75rem;`" " +
             "data-image=`"$imgRel`" " +
             "data-bounds=`"$boundsJson`" " +
             "data-minzoom=`"$($a.MinZoom)`" " +
             "data-maxzoom=`"$($a.MaxZoom)`" " +
             "data-defaultzoom=`"$($a.DefaultZoom)`" " +
             "data-lat=`"$($a.Lat)`" " +
             "data-long=`"$($a.Long)`" " +
             "data-geojson=`'$geoJsonArray`" " +
             "></div>")
  $lines.Add("")
  $lines.Add("<noscript>")
  $lines.Add("<p><em>Interactive map requires JavaScript. Here is the static map image:</em></p>")
  $lines.Add("![]($imgRel)")
  $lines.Add("</noscript>")
  $lines.Add("")
  $lines.Add("</details>")
  $lines.Add("")

  return ($lines -join "`n")
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
  "starred",

  # Never show (even if present in frontmatter)
  "ideas",
  "flaws",
  "fears",
  "mannerisms",
  "mannersisms",
  "alignment", 
  "current location",
  "languages",
  "condition" 
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
  "player"       = @("Played By","Character Sheet","Pronounced","Aliases","Ancestry","Heritage","Gender","Age","Height","Weight","Occupations","Organizations","Religions","Owned Locations")
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
# Also add common singular/plural aliases so "organization" matches "Organizations", etc.
$AllowKeyAliases = @{
  "organizations"    = @("organization")
  "organization"     = @("organizations")
  "owners"           = @("owner")
  "owner"            = @("owners")
  "locations"        = @("location")
  "location"         = @("locations")
  "religions"        = @("religion")
  "religion"         = @("religions")
  "occupations"      = @("occupation")
  "occupation"       = @("occupations")
  "creators"         = @("creator")
  "creator"          = @("creators")
  "previousowners"   = @("previousowner")
  "previousowner"    = @("previousowners")
  "rulers"           = @("ruler")
  "ruler"            = @("rulers")
  "leaders"          = @("leader")
  "leader"           = @("leaders")
  "defences"         = @("defence")
  "defence"          = @("defences")
  "imports"          = @("import")
  "import"           = @("imports")
  "exports"          = @("export")
  "export"           = @("exports")
}

$TypeAllow = @{}
foreach ($t in $TypeAllowRaw.Keys) {
  $TypeAllow[$t] = @{}
  foreach ($k in $TypeAllowRaw[$t]) {
    $nk = Normalize-Key $k
    if ($nk -eq "") { continue }

    $TypeAllow[$t][$nk] = $true

    if ($AllowKeyAliases.ContainsKey($nk)) {
      foreach ($a in $AllowKeyAliases[$nk]) {
        $na = Normalize-Key $a
        if ($na -ne "") { $TypeAllow[$t][$na] = $true }
      }
    }
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
      if ($FrontmatterBlacklist -contains ($k.ToString().ToLowerInvariant())) { continue }
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

# ---------- Asset indexing (helps resolve filename-only refs used by Leaflet/Obsidian) ----------

function Build-AssetIndex {
  param(
    [Parameter(Mandatory)] [string]$SourceVault
  )

  $idx = @{}
  $exts = @(".png",".jpg",".jpeg",".webp",".gif",".svg",".json")

  # Prefer indexing z_Assets (fast + most common), but fall back to full vault if not present.
  $roots = @()
  $zAssets = Join-Path $SourceVault "z_Assets"
  if (Test-Path -LiteralPath $zAssets) { $roots += $zAssets } else { $roots += $SourceVault }

  foreach ($root in $roots) {
    Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
      if ($exts -notcontains $_.Extension.ToLowerInvariant()) { return }
      $rel = $_.FullName.Substring($SourceVault.Length).TrimStart('\','/')
      $nameKey = $_.Name.ToLowerInvariant()

      if (-not $idx.ContainsKey($nameKey)) { $idx[$nameKey] = New-Object System.Collections.Generic.List[string] }
      [void]$idx[$nameKey].Add(($rel -replace '\\','/'))
    }
  }

  return $idx
}

function Resolve-AssetRelPath {
  param(
    [Parameter()] [string]$AssetRef,
    [Parameter()] [hashtable]$AssetIndex
  )

  if (-not $AssetRef) { return $null }

  # Strip wikilink wrappers if present
  $p = "$AssetRef".Trim()
  $p = $p.Trim('"').Trim("'")
  if ($p -match '^\[\[([^\]]+?)\]\]$') { $p = $Matches[1] }
  if ($p -match '^(.*?)\|') { $p = $Matches[1] } # drop alias

  $p = $p.Trim().TrimStart('/','\') -replace '\\','/'

  # If it already looks like a relative path, keep it
  if ($p -match '/'){ return $p }

  # Otherwise, try filename-only resolution
  if ($AssetIndex -and $AssetIndex.ContainsKey($p.ToLowerInvariant())) {
    $candidates = $AssetIndex[$p.ToLowerInvariant()]

    # Prefer z_Assets path if present
    $best = $null
    foreach ($c in $candidates) {
      if ($c -like "z_Assets/*") { $best = $c; break }
    }
    if (-not $best) { $best = $candidates[0] }
    return $best
  }

  return $p
}


function Copy-AssetIfExists {
  param(
    [string]$SourceVault,
    [string]$QuartzContentOut,
    [string]$AssetPath,
    [hashtable]$AssetIndex
  )
if (-not $AssetPath) { return }

  $assetRel = Resolve-AssetRelPath -AssetRef $AssetPath -AssetIndex $AssetIndex
  if (-not $assetRel) { return }
  $assetRel = $assetRel.Trim().TrimStart('/','\')
  $sourceAbs = Join-Path $SourceVault $assetRel

  if (Test-Path $sourceAbs) {
    $destAbs = Join-Path $QuartzContentOut $assetRel
    $destDir = Split-Path $destAbs -Parent
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    Copy-Item -Force -LiteralPath $sourceAbs -Destination $destAbs
    [void]$CopiedAssets.Add(($assetRel -replace '\\','/'))
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
    Copy-AssetIfExists -SourceVault $SourceVault -QuartzContentOut $QuartzContentOut -AssetPath $p -AssetIndex $AssetIndex
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

    Copy-AssetIfExists -SourceVault $SourceVault -QuartzContentOut $QuartzContentOut -AssetPath $p -AssetIndex $AssetIndex
  }

  # 3) Optional: HTML <img src="...">
  $m3 = [regex]::Matches($Text, '<img[^>]+src=["'']([^"''>]+)["'']', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  foreach ($x in $m3) {
    $p = $x.Groups[1].Value.Trim()

    if ($p -match '^(https?:)?//') { continue }
    if ($p -match '^data:') { continue }

    if ($p.StartsWith('/')) { $p = $p.Substring(1) }

    Copy-AssetIfExists -SourceVault $SourceVault -QuartzContentOut $QuartzContentOut -AssetPath $p -AssetIndex $AssetIndex
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
$CopiedAssets    = New-Object System.Collections.Generic.HashSet[string]  # assets copied this run

# Build an asset index so filename-only refs (common with Leaflet and Obsidian embeds) can be resolved reliably.
$AssetIndex = Build-AssetIndex -SourceVault $SourceVault



foreach ($f in $files) {
  $raw = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
  $raw = Strip-ObsidianComments $raw

  $fmBlock = Get-FrontmatterBlock $raw
  $fm = Parse-Frontmatter $fmBlock

  if (-not (Normalize-Bool $fm["player_visible"])) { continue }

  $playerText = Extract-PlayerBlocks $raw
  if (-not $playerText) { continue } # require player blocks for safety

    $title = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
  $infobox = Build-InfoboxMarkdown -Title $title -fm $fm

  # Optional: export Leaflet map (image + GeoJSON references) as a static section for players
  $mapSection = Build-MapSectionMarkdown -RawNoteText $raw -AssetIndex $AssetIndex

  # Copy frontmatter art + any embeds inside player text (and map section if present)
  Copy-AssetIfExists -SourceVault $SourceVault -QuartzContentOut $QuartzContentOut -AssetPath $fm["art"] -AssetIndex $AssetIndex
  if ($mapSection) {
    Copy-EmbeddedAssetsFromText -SourceVault $SourceVault -QuartzContentOut $QuartzContentOut -Text $mapSection

    # Copy linked GeoJSON files (markdown links won't be caught by image/embed scanners)
    $jm = [regex]::Matches($mapSection, '\(/([^)\s]+?\.json)\)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    foreach ($x in $jm) {
      Copy-AssetIfExists -SourceVault $SourceVault -QuartzContentOut $QuartzContentOut -AssetPath $x.Groups[1].Value -AssetIndex $AssetIndex
    }
  }
  Copy-EmbeddedAssetsFromText -SourceVault $SourceVault -QuartzContentOut $QuartzContentOut -Text $playerText


  # Preserve relative structure from scope root
  $relative = $f.FullName.Substring($root.Length).TrimStart('\','/')
  $relNorm = $relative -replace '\\','/'   # Quartz-friendly
  $ExportedRelPaths.Add($relNorm) | Out-Null
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
  if ($mapSection) {
    $out += $mapSection.Trim()
    $out += ""
  }
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


# ---------- Optional: write list of exported pages ----------
if ($WriteExportList) {
  $listPath = Join-Path $QuartzContentOut "_exported-files.txt"
  $ExportedRelPaths |
    Sort-Object |
    Set-Content -LiteralPath $listPath -Encoding UTF8
}

# ---------- Optional: clean stale markdown from previous exports ----------
# Removes *.md files under the Quartz content folder that were NOT exported this run.
# Safety exclusions: index pages, _Indexes, and export report files.
if ($CleanStaleContent) {
  $keep = New-Object System.Collections.Generic.HashSet[string]
  $ExportedRelPaths | ForEach-Object { [void]$keep.Add($_) }

  $existingMd = Get-ChildItem -LiteralPath $QuartzContentOut -Recurse -File -Filter "*.md" -ErrorAction SilentlyContinue
  $stale = New-Object System.Collections.Generic.List[string]

  foreach ($file in $existingMd) {
    $rel = $file.FullName.Substring($QuartzContentOut.Length).TrimStart('\','/') -replace '\\','/'

    if ($rel -match '^_Indexes(/|$)') { continue }
    if ($rel -match '^index\.md$' -or $rel -match '/index\.md$') { continue }
    if ($rel -match '^_export-report\.txt$') { continue }
    if ($rel -match '^_exported-files\.txt$') { continue }

    if (-not $keep.Contains($rel)) {
      $stale.Add($rel) | Out-Null
      if (-not $ValidateOnly) {
        Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
      }
    }
  }

  if ($stale.Count -gt 0) {
    $dry = if ($ValidateOnly) { "(dry-run) " } else { "" }
    $Info.Add(("CLEAN: stale markdown " + $dry + "removed: " + $stale.Count)) | Out-Null
  }
}

# ---------- Optional: clean orphan assets ----------
# Treats any file under z_Assets as "in-scope" assets. If not copied this run, it is considered orphaned.
if ($CleanOrphanAssets) {
  $assetRoot = Join-Path $QuartzContentOut "z_Assets"
  if (Test-Path $assetRoot) {
    $assets = Get-ChildItem -LiteralPath $assetRoot -Recurse -File -ErrorAction SilentlyContinue
    $orphans = New-Object System.Collections.Generic.List[string]

    foreach ($a in $assets) {
      $rel = $a.FullName.Substring($QuartzContentOut.Length).TrimStart('\','/') -replace '\\','/'
      if (-not $CopiedAssets.Contains($rel)) {
        $orphans.Add($rel) | Out-Null
        if (-not $ValidateOnly) {
          Remove-Item -LiteralPath $a.FullName -Force -ErrorAction SilentlyContinue
        }
      }
    }

    if ($orphans.Count -gt 0) {
      $dry = if ($ValidateOnly) { "(dry-run) " } else { "" }
      $Info.Add(("CLEAN: orphan assets " + $dry + "removed: " + $orphans.Count)) | Out-Null
    }
  }
}



Write-Host "Export complete: $(Get-Date)"


# SIG # Begin signature block
# MIIb7AYJKoZIhvcNAQcCoIIb3TCCG9kCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUQCZSt0cEWHEt4gNBGNXUvtjb
# 9k2gghZUMIIDFjCCAf6gAwIBAgIQcPphZdBOpIhOhIcru1JmKTANBgkqhkiG9w0B
# AQsFADAjMSEwHwYDVQQDDBhMb2NhbCBQb3dlclNoZWxsIFNjcmlwdHMwHhcNMjYw
# MTI4MjA1OTQyWhcNMjcwMTI4MjExOTQyWjAjMSEwHwYDVQQDDBhMb2NhbCBQb3dl
# clNoZWxsIFNjcmlwdHMwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDi
# LpTC2Nl/BVo7hxX+9qqU7CHwK9TcEFzxiiy+LnURv2I6i5vJfE7i8DHF0L0q3rsb
# Sa0gVyDtmPgHyBIcesW+RIvv/rn8Ggwd77fU9JlwhN0kSpExySWHX/cGW2U2NjaU
# u6rRa0bVoIqR7NUMqiwtWRw1WUPlnAhXHuyXajfNDge+fZ81So6rEz9gKssdIxg/
# +zaQfy9sVIZL1iddLNUx4YDjWhM0qVF4ByfcWLJGeLc2B793RiKzm7YOgvwo+hNu
# KUASvpmpOSBRPigJzKX/t0Y/Je8cR6sdYj26RqqJCWhUpwQjqZDbqLuFctWUddBu
# cz0K30DRtemO5iAedjqBAgMBAAGjRjBEMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUE
# DDAKBggrBgEFBQcDAzAdBgNVHQ4EFgQU1s1lOVpSMSSCgS7l3NHMON4i3I4wDQYJ
# KoZIhvcNAQELBQADggEBAGukQPwUQHi6KS/T4LpTm6janaFoACHL8IFsLdsimXKL
# U8qoSl30uM+CTEYV1QloB41lhyJyUutYkjIqZDgA7Uk793mgot3pv0d0nYCrxVMS
# U8DQupRGzYiI0XPCHybr1dAHiGlD7RlykmS+8J3uH9rsa+xXcQeH/Vr1e4jgvhRv
# WEIGKQtieA4Ps5hsBGGGHgW7SJz5jeVryfXNuI52/QEa/ohRs4XDJYMe7p5urRKg
# Ckk/Oex81lGRRgQwfWadt7TIiqNovyr+XPADGu9w594PRuupjWMpDHDth3XnDHVZ
# ntGcyXIpJUfZVF5zbxfZqi9aOgaVPc4aRI1O1bLKehcwggWNMIIEdaADAgECAhAO
# mxiO+dAt5+/bUOIIQBhaMA0GCSqGSIb3DQEBDAUAMGUxCzAJBgNVBAYTAlVTMRUw
# EwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20x
# JDAiBgNVBAMTG0RpZ2lDZXJ0IEFzc3VyZWQgSUQgUm9vdCBDQTAeFw0yMjA4MDEw
# MDAwMDBaFw0zMTExMDkyMzU5NTlaMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxE
# aWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMT
# GERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDCCAiIwDQYJKoZIhvcNAQEBBQADggIP
# ADCCAgoCggIBAL/mkHNo3rvkXUo8MCIwaTPswqclLskhPfKK2FnC4SmnPVirdprN
# rnsbhA3EMB/zG6Q4FutWxpdtHauyefLKEdLkX9YFPFIPUh/GnhWlfr6fqVcWWVVy
# r2iTcMKyunWZanMylNEQRBAu34LzB4TmdDttceItDBvuINXJIB1jKS3O7F5OyJP4
# IWGbNOsFxl7sWxq868nPzaw0QF+xembud8hIqGZXV59UWI4MK7dPpzDZVu7Ke13j
# rclPXuU15zHL2pNe3I6PgNq2kZhAkHnDeMe2scS1ahg4AxCN2NQ3pC4FfYj1gj4Q
# kXCrVYJBMtfbBHMqbpEBfCFM1LyuGwN1XXhm2ToxRJozQL8I11pJpMLmqaBn3aQn
# vKFPObURWBf3JFxGj2T3wWmIdph2PVldQnaHiZdpekjw4KISG2aadMreSx7nDmOu
# 5tTvkpI6nj3cAORFJYm2mkQZK37AlLTSYW3rM9nF30sEAMx9HJXDj/chsrIRt7t/
# 8tWMcCxBYKqxYxhElRp2Yn72gLD76GSmM9GJB+G9t+ZDpBi4pncB4Q+UDCEdslQp
# JYls5Q5SUUd0viastkF13nqsX40/ybzTQRESW+UQUOsxxcpyFiIJ33xMdT9j7CFf
# xCBRa2+xq4aLT8LWRV+dIPyhHsXAj6KxfgommfXkaS+YHS312amyHeUbAgMBAAGj
# ggE6MIIBNjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTs1+OC0nFdZEzfLmc/
# 57qYrhwPTzAfBgNVHSMEGDAWgBRF66Kv9JLLgjEtUYunpyGd823IDzAOBgNVHQ8B
# Af8EBAMCAYYweQYIKwYBBQUHAQEEbTBrMCQGCCsGAQUFBzABhhhodHRwOi8vb2Nz
# cC5kaWdpY2VydC5jb20wQwYIKwYBBQUHMAKGN2h0dHA6Ly9jYWNlcnRzLmRpZ2lj
# ZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcnQwRQYDVR0fBD4wPDA6
# oDigNoY0aHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0QXNzdXJlZElE
# Um9vdENBLmNybDARBgNVHSAECjAIMAYGBFUdIAAwDQYJKoZIhvcNAQEMBQADggEB
# AHCgv0NcVec4X6CjdBs9thbX979XB72arKGHLOyFXqkauyL4hxppVCLtpIh3bb0a
# FPQTSnovLbc47/T/gLn4offyct4kvFIDyE7QKt76LVbP+fT3rDB6mouyXtTP0UNE
# m0Mh65ZyoUi0mcudT6cGAxN3J0TU53/oWajwvy8LpunyNDzs9wPHh6jSTEAZNUZq
# aVSwuKFWjuyk1T3osdz9HNj0d1pcVIxv76FQPfx2CWiEn2/K2yCNNWAcAgPLILCs
# WKAOQGPFmCLBsln1VWvPJ6tsds5vIy30fnFqI2si/xK4VC0nftg62fC2h5b9W9Fc
# rBjDTZ9ztwGpn1eqXijiuZQwgga0MIIEnKADAgECAhANx6xXBf8hmS5AQyIMOkmG
# MA0GCSqGSIb3DQEBCwUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxEaWdpQ2Vy
# dCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMTGERpZ2lD
# ZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0yNTA1MDcwMDAwMDBaFw0zODAxMTQyMzU5
# NTlaMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8G
# A1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBT
# SEEyNTYgMjAyNSBDQTEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC0
# eDHTCphBcr48RsAcrHXbo0ZodLRRF51NrY0NlLWZloMsVO1DahGPNRcybEKq+Ruw
# OnPhof6pvF4uGjwjqNjfEvUi6wuim5bap+0lgloM2zX4kftn5B1IpYzTqpyFQ/4B
# t0mAxAHeHYNnQxqXmRinvuNgxVBdJkf77S2uPoCj7GH8BLuxBG5AvftBdsOECS1U
# kxBvMgEdgkFiDNYiOTx4OtiFcMSkqTtF2hfQz3zQSku2Ws3IfDReb6e3mmdglTca
# arps0wjUjsZvkgFkriK9tUKJm/s80FiocSk1VYLZlDwFt+cVFBURJg6zMUjZa/zb
# CclF83bRVFLeGkuAhHiGPMvSGmhgaTzVyhYn4p0+8y9oHRaQT/aofEnS5xLrfxnG
# pTXiUOeSLsJygoLPp66bkDX1ZlAeSpQl92QOMeRxykvq6gbylsXQskBBBnGy3tW/
# AMOMCZIVNSaz7BX8VtYGqLt9MmeOreGPRdtBx3yGOP+rx3rKWDEJlIqLXvJWnY0v
# 5ydPpOjL6s36czwzsucuoKs7Yk/ehb//Wx+5kMqIMRvUBDx6z1ev+7psNOdgJMoi
# wOrUG2ZdSoQbU2rMkpLiQ6bGRinZbI4OLu9BMIFm1UUl9VnePs6BaaeEWvjJSjNm
# 2qA+sdFUeEY0qVjPKOWug/G6X5uAiynM7Bu2ayBjUwIDAQABo4IBXTCCAVkwEgYD
# VR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQU729TSunkBnx6yuKQVvYv1Ensy04w
# HwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYDVR0PAQH/BAQDAgGG
# MBMGA1UdJQQMMAoGCCsGAQUFBwMIMHcGCCsGAQUFBwEBBGswaTAkBggrBgEFBQcw
# AYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAChjVodHRwOi8v
# Y2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNydDBD
# BgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5jb20vRGlnaUNl
# cnRUcnVzdGVkUm9vdEc0LmNybDAgBgNVHSAEGTAXMAgGBmeBDAEEAjALBglghkgB
# hv1sBwEwDQYJKoZIhvcNAQELBQADggIBABfO+xaAHP4HPRF2cTC9vgvItTSmf83Q
# h8WIGjB/T8ObXAZz8OjuhUxjaaFdleMM0lBryPTQM2qEJPe36zwbSI/mS83afsl3
# YTj+IQhQE7jU/kXjjytJgnn0hvrV6hqWGd3rLAUt6vJy9lMDPjTLxLgXf9r5nWMQ
# wr8Myb9rEVKChHyfpzee5kH0F8HABBgr0UdqirZ7bowe9Vj2AIMD8liyrukZ2iA/
# wdG2th9y1IsA0QF8dTXqvcnTmpfeQh35k5zOCPmSNq1UH410ANVko43+Cdmu4y81
# hjajV/gxdEkMx1NKU4uHQcKfZxAvBAKqMVuqte69M9J6A47OvgRaPs+2ykgcGV00
# TYr2Lr3ty9qIijanrUR3anzEwlvzZiiyfTPjLbnFRsjsYg39OlV8cipDoq7+qNNj
# qFzeGxcytL5TTLL4ZaoBdqbhOhZ3ZRDUphPvSRmMThi0vw9vODRzW6AxnJll38F0
# cuJG7uEBYTptMSbhdhGQDpOXgpIUsWTjd6xpR6oaQf/DJbg3s6KCLPAlZ66RzIg9
# sC+NJpud/v4+7RWsWCiKi9EOLLHfMR2ZyJ/+xhCx9yHbxtl5TPau1j/1MIDpMPx0
# LckTetiSuEtQvLsNz3Qbp7wGWqbIiOWCnb5WqxL3/BAPvIXKUjPSxyZsq8WhbaM2
# tszWkPZPubdcMIIG7TCCBNWgAwIBAgIQCoDvGEuN8QWC0cR2p5V0aDANBgkqhkiG
# 9w0BAQsFADBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4x
# QTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQw
# OTYgU0hBMjU2IDIwMjUgQ0ExMB4XDTI1MDYwNDAwMDAwMFoXDTM2MDkwMzIzNTk1
# OVowYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYD
# VQQDEzJEaWdpQ2VydCBTSEEyNTYgUlNBNDA5NiBUaW1lc3RhbXAgUmVzcG9uZGVy
# IDIwMjUgMTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBANBGrC0Sxp7Q
# 6q5gVrMrV7pvUf+GcAoB38o3zBlCMGMyqJnfFNZx+wvA69HFTBdwbHwBSOeLpvPn
# Z8ZN+vo8dE2/pPvOx/Vj8TchTySA2R4QKpVD7dvNZh6wW2R6kSu9RJt/4QhguSss
# p3qome7MrxVyfQO9sMx6ZAWjFDYOzDi8SOhPUWlLnh00Cll8pjrUcCV3K3E0zz09
# ldQ//nBZZREr4h/GI6Dxb2UoyrN0ijtUDVHRXdmncOOMA3CoB/iUSROUINDT98ok
# souTMYFOnHoRh6+86Ltc5zjPKHW5KqCvpSduSwhwUmotuQhcg9tw2YD3w6ySSSu+
# 3qU8DD+nigNJFmt6LAHvH3KSuNLoZLc1Hf2JNMVL4Q1OpbybpMe46YceNA0LfNsn
# qcnpJeItK/DhKbPxTTuGoX7wJNdoRORVbPR1VVnDuSeHVZlc4seAO+6d2sC26/PQ
# PdP51ho1zBp+xUIZkpSFA8vWdoUoHLWnqWU3dCCyFG1roSrgHjSHlq8xymLnjCbS
# LZ49kPmk8iyyizNDIXj//cOgrY7rlRyTlaCCfw7aSUROwnu7zER6EaJ+AliL7ojT
# dS5PWPsWeupWs7NpChUk555K096V1hE0yZIXe+giAwW00aHzrDchIc2bQhpp0IoK
# RR7YufAkprxMiXAJQ1XCmnCfgPf8+3mnAgMBAAGjggGVMIIBkTAMBgNVHRMBAf8E
# AjAAMB0GA1UdDgQWBBTkO/zyMe39/dfzkXFjGVBDz2GM6DAfBgNVHSMEGDAWgBTv
# b1NK6eQGfHrK4pBW9i/USezLTjAOBgNVHQ8BAf8EBAMCB4AwFgYDVR0lAQH/BAww
# CgYIKwYBBQUHAwgwgZUGCCsGAQUFBwEBBIGIMIGFMCQGCCsGAQUFBzABhhhodHRw
# Oi8vb2NzcC5kaWdpY2VydC5jb20wXQYIKwYBBQUHMAKGUWh0dHA6Ly9jYWNlcnRz
# LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNFRpbWVTdGFtcGluZ1JTQTQw
# OTZTSEEyNTYyMDI1Q0ExLmNydDBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vY3Js
# My5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRUaW1lU3RhbXBpbmdSU0E0
# MDk2U0hBMjU2MjAyNUNBMS5jcmwwIAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJYIZI
# AYb9bAcBMA0GCSqGSIb3DQEBCwUAA4ICAQBlKq3xHCcEua5gQezRCESeY0ByIfjk
# 9iJP2zWLpQq1b4URGnwWBdEZD9gBq9fNaNmFj6Eh8/YmRDfxT7C0k8FUFqNh+tsh
# gb4O6Lgjg8K8elC4+oWCqnU/ML9lFfim8/9yJmZSe2F8AQ/UdKFOtj7YMTmqPO9m
# zskgiC3QYIUP2S3HQvHG1FDu+WUqW4daIqToXFE/JQ/EABgfZXLWU0ziTN6R3ygQ
# BHMUBaB5bdrPbF6MRYs03h4obEMnxYOX8VBRKe1uNnzQVTeLni2nHkX/QqvXnNb+
# YkDFkxUGtMTaiLR9wjxUxu2hECZpqyU1d0IbX6Wq8/gVutDojBIFeRlqAcuEVT0c
# Ksb+zJNEsuEB7O7/cuvTQasnM9AWcIQfVjnzrvwiCZ85EE8LUkqRhoS3Y50OHgaY
# 7T/lwd6UArb+BOVAkg2oOvol/DJgddJ35XTxfUlQ+8Hggt8l2Yv7roancJIFcboj
# BcxlRcGG0LIhp6GvReQGgMgYxQbV1S3CrWqZzBt1R9xJgKf47CdxVRd/ndUlQ05o
# xYy2zRWVFjF7mcr4C34Mj3ocCVccAvlKV9jEnstrniLvUxxVZE/rptb7IRE2lskK
# PIJgbaP5t2nGj/ULLi49xTcBZU8atufk+EMF/cWuiC7POGT75qaL6vdCvHlshtjd
# NXOCIUjsarfNZzGCBQIwggT+AgEBMDcwIzEhMB8GA1UEAwwYTG9jYWwgUG93ZXJT
# aGVsbCBTY3JpcHRzAhBw+mFl0E6kiE6Ehyu7UmYpMAkGBSsOAwIaBQCgeDAYBgor
# BgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEE
# MBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBQC
# GFlcTdBWKOpLZON4LhcrLs4o6TANBgkqhkiG9w0BAQEFAASCAQA7CBcjQkbus10L
# pTPVOaAVlk9WZa6+8vzw9r1KaQWFZRsFR01xYZaMIfihrsi0hzQ7/pI75U4t5q5o
# gZmMY94HPzpSlt5FZxMVx+HWI2zwGpBNqxDNeNWjsja81MoxKZF3i0smklG7JBqX
# fM10p3tllnOQVQgBCz+aRP6CtQ1aRK7OWv/jDQMCgStloRnpwVZCj903oX386x68
# 1zQcV1HmqMnoDNRCqRzhR3cz6i1MFg8ovWR2+fF5EHUjxKqHILPt21uOUIy1KLIw
# Xx5P4OcE+bfq2GuFV8GhVoE88mO29J+m6mCDeG8MFtBnMymrQniaIPE8lDCafSjX
# RSlVqYu0oYIDJjCCAyIGCSqGSIb3DQEJBjGCAxMwggMPAgEBMH0waTELMAkGA1UE
# BhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdpQ2Vy
# dCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBSU0E0MDk2IFNIQTI1NiAyMDI1IENB
# MQIQCoDvGEuN8QWC0cR2p5V0aDANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJ
# AzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTI2MDMxMTE5MzcxM1owLwYJ
# KoZIhvcNAQkEMSIEIABcFP0dPYG7ec0qNUaVQIW2tM+0/bknPy60HI7WQHlmMA0G
# CSqGSIb3DQEBAQUABIICAEtS47E3/9YNO9czzywmgJg0jyKmwbJuk9OdqGtS2eBa
# u+KX6f61Rsk7Mp2uVIV0abrz/lLCoJdywzJ4m+WPQU+LBixVyEkxDWsFLBNApGzI
# hXjqgC8wZcn8zAs9g7fYk+HG6eUql73YfVZzfxEZNLZ/n9FxI7UIezDvoYlC1KuO
# 4s6i53FXDe0X9BhqK26lXHujT1i1V5YA/rBT/tkwUGQiazaTg2mLjQ8P4wlqsKDN
# IfQx7G3pfY4W74Eh0Gq5JpRQ09LATF7em+eA5K7jd3yJ4CCpoLCY1ib9rHafYFS9
# uAIKoj/FNXSFtlKX+yIt0EON0nFWI66xKL0kXv3EqzHMd2ygFnSwrgvKsi+wYv7D
# yRy8RUzoPsO2HM76PBJ5ynVsJAhF3qwjjU7WratGqDKQwxzJuuo4sQKmr9w8wrky
# p6mBRcjaLozHunTtsVGYTU4EZpCwBQpJXX1SmSYI6/A49oPmp2pTY4vpccEZWkYw
# 5uOQS+3okziFg91h+KkzJN26RPHYg/DedgdvXxaFNUT4MWRssp8pNFBtifaKZ0nJ
# B28od5HVLTfyfVXaeuGnm6d5NEc8z6CBL6LOxQfyveNDWkKkHGClDxMO8y/sst6G
# /IBNPUi/pz2phkYKedh+tbY/RH46CJXh4Ou6x3gil5x2MbPwLbboceI3J8B6Hqy+
# SIG # End signature block
