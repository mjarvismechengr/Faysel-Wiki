$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert |
  Sort-Object NotAfter -Descending |
  Select-Object -First 1

if (-not $cert) { throw "No code signing certificate found in CurrentUser\My." }

$ts = "http://timestamp.digicert.com"

Set-AuthenticodeSignature -FilePath ".\Export-PlayerWiki.ps1" -Certificate $cert -TimestampServer $ts | Out-Null
Set-AuthenticodeSignature -FilePath ".\Run-PlayerWiki.ps1" -Certificate $cert -TimestampServer $ts | Out-Null

"Signed scripts with: $($cert.Subject)"