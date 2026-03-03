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

# SIG # Begin signature block
# MIIb7AYJKoZIhvcNAQcCoIIb3TCCG9kCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU27o9ioWpEYmCNaqZtLfCAab1
# Q6qgghZUMIIDFjCCAf6gAwIBAgIQcPphZdBOpIhOhIcru1JmKTANBgkqhkiG9w0B
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
# MBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBRu
# YWff0dmCL5tdqd8vWP2Y+jIHnDANBgkqhkiG9w0BAQEFAASCAQAXPqG44M20keMn
# RHkihlU0HxEz7OSDfJXRi4NOL9T2DxeY6vJp5UETBifuXXNWL3ccBcpum52k2aJz
# QqRW80nIg2eHPxeER10vBq0as9S2VmCiYcxMRMAlC7y2UIxHPKVVtwC8fjFDmQiO
# PTUxbOz0pSehJo7C2s9mQcko668Lc6RYARva6AOvLoQ17FwxyR15hzJGOTSzfOxU
# bVbPMa0Vf5xLeFf6GKzETww3PbYh6NAfrpmeRFF9UawGrNgBOgK2ZS6iAzULVzsa
# 2RBpDkvtwUbz+1yEji5yvwlYr+lbeFrEDAk5aSNB6Hs8VtFeZmWcvuYNLtLSnh8D
# aX/ThC0noYIDJjCCAyIGCSqGSIb3DQEJBjGCAxMwggMPAgEBMH0waTELMAkGA1UE
# BhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdpQ2Vy
# dCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBSU0E0MDk2IFNIQTI1NiAyMDI1IENB
# MQIQCoDvGEuN8QWC0cR2p5V0aDANBglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJ
# AzELBgkqhkiG9w0BBwEwHAYJKoZIhvcNAQkFMQ8XDTI2MDMwMzE4MzAyMlowLwYJ
# KoZIhvcNAQkEMSIEIIT56yEDdQMKWTgtQ2pmBOBT8BlpHSzUBdQd77++isq5MA0G
# CSqGSIb3DQEBAQUABIICAMDOPB1pf4MAXJtgJbgOa1FJP+shrzY/r3dcOmhglfQG
# +SikWbUVxI1TflsxtGlABBAtRuloInT9kagsWqus9mivuApUeAyW1JS/HKkStL2n
# nN2NZUwVcagviu0HjW2vo5dnhypQ+1+O18OGCL51drZ5eYR5C4JsO+X/8U5oW05M
# 92ACIo5HTEGTOH0r91J6cNXuPIBq8cdZRHSC9hPA3NRkg2P9ZAOpnAN/iVOX5Q+o
# n7YslTWJ1meX79gitGNzMI2dFlrpBWEKDhlXy7cMeXu9QVwXx6Aqbk5RWhHw8OWr
# Wy434uGZof0AwOjP++smdspOneEsm6M7AWQKWmuMZ8lJDWgMdtm7WxBwvPFrSMyV
# mWaH9vyh/e9bgksoyNfXxNn4QWHq8oI791kIHhF1fpRf+O2dza88lnF1YBQMm5wL
# sAgKpg3uGw55Dy6djjYG5bEwzL3BFHkPU00JoDyo7WO5FqUIXxfdetRCeBPNRUky
# tvEDkYP77xI29bZFMqFg0nnLwNp3CfJWNzqWzvDEfdly5XcG+hS+TvJ8t7IMRyzs
# 1bcJTcJ9Eh7UxpoGzMsRzplVONCf+3WU4k+sfRdNT37mhhxpUzV0BJ49AM58EURZ
# 49NOru/Ji+g2wzPOdjMPvA3Z7yPyyxwgyXIcDqzfqLG06y1iXlaOF+MtyRMEoTdY
# SIG # End signature block
