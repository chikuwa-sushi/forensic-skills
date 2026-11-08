<#
Download tools listed in tools.lock into .\tools (git-ignored).
  .\scripts\setup.ps1            install missing tools
  .\scripts\setup.ps1 -Force     re-download all
  .\scripts\setup.ps1 -ShowHash  print SHA256 of downloaded zips
#>
param([switch]$Force, [switch]$ShowHash, [switch]$DefenderExclude)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root  = Split-Path $PSScriptRoot -Parent
$lock  = & (Join-Path $PSScriptRoot 'Get-Config.ps1') -EnvPath (Join-Path $root 'tools.lock')
$tools = Join-Path $root 'tools'
$dl    = Join-Path $tools '_download'
$log   = Join-Path $tools 'installed.txt'
New-Item -ItemType Directory -Force $dl | Out-Null

# Skills live in .agents\skills (Codex etc.). Claude Code reads .claude\skills -> junction (no admin needed).
$skillLink   = Join-Path $root '.claude\skills'
$skillTarget = Join-Path $root '.agents\skills'
if (-not (Test-Path -LiteralPath $skillLink)) {
    New-Item -ItemType Junction -Path $skillLink -Target $skillTarget | Out-Null
    Write-Host 'Created junction .claude\skills -> .agents\skills'
} elseif (-not ((Get-Item -LiteralPath $skillLink -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    Write-Warning '.claude\skills is a real folder. Edit .agents\skills (source of truth) and replace it with a junction.'
}

function Install-Zip([string]$Name, [string]$Url, [string]$Expected, [string]$Dest, [string]$Check, [string[]]$Skip) {
    if (-not $Force -and (Test-Path -LiteralPath $Check)) { Write-Host "[$Name] already installed"; return }
    $zip = Join-Path $dl "$Name.zip"
    Write-Host "[$Name] download $Url"
    try { Invoke-WebRequest -UseBasicParsing $Url -OutFile $zip }
    catch { throw "[$Name] download failed: $($_.Exception.Message). If the version was removed, update tools.lock." }

    $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
    if ($ShowHash) { Write-Host "[$Name] SHA256=$hash" }
    if ($Expected) {
        if ($hash -ne $Expected.ToUpper()) { Remove-Item -LiteralPath $zip; throw "[$Name] SHA256 mismatch. expected=$Expected actual=$hash" }
    } else { Write-Warning "[$Name] hash not pinned. SHA256=$hash" }

    $destFull = [IO.Path]::GetFullPath($Dest).TrimEnd('\') + '\'
    $z = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        foreach ($e in $z.Entries) {
            if ($Skip | Where-Object { $e.Name -like $_ }) { continue }
            $out = [IO.Path]::GetFullPath((Join-Path $destFull $e.FullName))
            if (-not $out.StartsWith($destFull, [StringComparison]::OrdinalIgnoreCase)) { throw "[$Name] unsafe path in zip: $($e.FullName)" }
            if ($e.FullName.EndsWith('/')) { New-Item -ItemType Directory -Force $out | Out-Null; continue }
            New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $out, $true)
        }
    } catch {
        throw "[$Name] extract failed: $($_.Exception.Message). Antivirus may have blocked a file."
    } finally { $z.Dispose() }
    Add-Content -LiteralPath $log -Value "$(Get-Date -Format s)`t$Name`t$Url`t$hash`t$(Get-ToolVersion $Name)"
    Write-Host "[$Name] installed"
}

# Version from the executable's metadata. installed.txt columns: date, name, url, sha256, version
function Get-ToolVersion([string]$Name) {
    $exe = Get-ChildItem -LiteralPath $tools -Recurse -Filter "$Name.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($exe -and $exe.VersionInfo.ProductVersion) { $exe.VersionInfo.ProductVersion.Trim() } else { 'unknown' }
}

# 7-Zip needs 7z.exe + 7z.dll: the standalone 7za.exe has no VHDX/Ext support.
# The MSI is unpacked with an administrative install (/a), so nothing is registered on the system.
function Install-7Zip([string]$Url, [string]$Expected, [string]$Dest) {
    if (-not $Force -and (Test-Path -LiteralPath (Join-Path $Dest '7z.exe'))) { Write-Host '[7z] already installed'; return }
    if (-not $Expected) { throw '[7z] SEVENZIP_SHA256 is required in tools.lock' }
    $msi = Join-Path $dl '7z.msi'
    $tmp = Join-Path $dl '7z_unpack'
    Write-Host "[7z] download $Url"
    try { Invoke-WebRequest -UseBasicParsing $Url -OutFile $msi }
    catch { throw "[7z] download failed: $($_.Exception.Message). If the version was removed, update tools.lock." }

    $hash = (Get-FileHash -LiteralPath $msi -Algorithm SHA256).Hash
    if ($ShowHash) { Write-Host "[7z] SHA256=$hash" }
    if ($hash -ne $Expected.ToUpper()) { Remove-Item -LiteralPath $msi; throw "[7z] SHA256 mismatch. expected=$Expected actual=$hash" }

    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
    $p = Start-Process msiexec.exe -ArgumentList "/a `"$msi`" /qn TARGETDIR=`"$tmp`"" -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "[7z] msiexec failed (exit=$($p.ExitCode))" }
    $src = Get-ChildItem -LiteralPath $tmp -Recurse -Filter '7z.exe' | Select-Object -First 1
    if (-not $src) { throw '[7z] 7z.exe not found in the MSI' }
    New-Item -ItemType Directory -Force $Dest | Out-Null
    foreach ($f in '7z.exe', '7z.dll', 'License.txt') { Copy-Item -LiteralPath (Join-Path $src.DirectoryName $f) $Dest -Force }
    Remove-Item -LiteralPath $tmp -Recurse -Force
    Add-Content -LiteralPath $log -Value "$(Get-Date -Format s)`t7z`t$Url`t$hash`t$(Get-ToolVersion '7z')"
    Write-Host '[7z] installed'
}

# CDIR-C (winpmem is not needed: memory dump is disabled)
Install-Zip 'cdir-collector' $lock.CDIRC_URL $lock.CDIRC_SHA256 $tools `
    (Join-Path $tools 'cdir-collector\cdir-collector.exe') @('winpmem*')

# Eric Zimmerman Tools
$ez = Join-Path $tools 'ez'
foreach ($t in ($lock.EZ_TOOLS -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
    $exe = Get-ChildItem -LiteralPath $ez -Recurse -Filter "$t.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    $check = if ($exe) { $exe.FullName } else { Join-Path $ez "$t.exe" }
    Install-Zip $t "$($lock.EZ_BASE_URL)/$t.zip" $lock["EZ_SHA256_$t"] $ez $check @()
}

# NirSoft browser tools
$ns = Join-Path $tools 'nirsoft'
# BrowsingHistoryView (browser history; parse-browser skill)
if ($lock.BROWSERHISTORYVIEW_URL) {
    Install-Zip 'BrowsingHistoryView' $lock.BROWSERHISTORYVIEW_URL $lock.BROWSERHISTORYVIEW_SHA256 $ns `
        (Join-Path $ns 'BrowsingHistoryView.exe') @()
}
# BrowserDownloadsView (browser downloads; parse-browser-downloads skill)
if ($lock.BROWSERDOWNLOADSVIEW_URL) {
    Install-Zip 'BrowserDownloadsView' $lock.BROWSERDOWNLOADSVIEW_URL $lock.BROWSERDOWNLOADSVIEW_SHA256 $ns `
        (Join-Path $ns 'BrowserDownloadsView.exe') @()
}

# 7-Zip (view-vhdx skill)
if ($lock.SEVENZIP_URL) { Install-7Zip $lock.SEVENZIP_URL $lock.SEVENZIP_SHA256 (Join-Path $tools '7zip') }

# Fill in the version on rows written before the version column existed (latest row of each tool only)
if (Test-Path -LiteralPath $log) {
    $rows = @(Get-Content -LiteralPath $log)
    $latest = @{}
    for ($i = 0; $i -lt $rows.Count; $i++) { $latest[($rows[$i] -split "`t")[1]] = $i }
    foreach ($i in @($latest.Values)) {
        $f = $rows[$i] -split "`t"
        if ($f.Count -eq 4) { $rows[$i] += "`t" + (Get-ToolVersion $f[1]) }
    }
    Set-Content -LiteralPath $log -Value $rows
}

# .NET runtime check (EZ Tools net build requires .NET 10)
$rt = try { & dotnet --list-runtimes 2>$null } catch { $null }
if (-not ($rt -match 'Microsoft\.NETCore\.App 10\.')) { Write-Warning '.NET 10 runtime not found. EZ Tools will not run without it.' }

# .env
$envFile = Join-Path $root '.env'
if (-not (Test-Path -LiteralPath $envFile)) {
    Copy-Item (Join-Path $root '.env.example') $envFile
    Write-Host 'Created .env from .env.example. Edit COLLECT_DIR / PARSED_DIR if needed.'
}

# Python venv (補助解析スクリプト用: ブラウザ SQLite / PDF / SAM ハッシュ / NTLM など)
# 証拠データを扱う Python はシステム環境を汚さず、この venv (.env の PYTHON) で実行する。
$venv   = Join-Path $root '.venv'
$venvPy = Join-Path $venv 'Scripts\python.exe'
$py = $null
foreach ($cand in 'python', 'py') {
    $c = Get-Command $cand -ErrorAction SilentlyContinue
    if ($c) { $py = $c.Source; break }
}
if (-not $py) {
    Write-Warning 'Python not found. Install Python 3 to use auxiliary analysis scripts (.venv skipped).'
} else {
    if ($Force -and (Test-Path -LiteralPath $venv)) { Remove-Item -Recurse -Force $venv }
    if (-not (Test-Path -LiteralPath $venvPy)) {
        Write-Host '[venv] creating .venv'
        & $py -m venv $venv
    }
    if (Test-Path -LiteralPath $venvPy) {
        # impacket is flagged by Windows Defender as HackTool:Python/Impacket and gets quarantined
        # mid-install. -DefenderExclude (admin) adds .venv to the exclusion list so it can install/run.
        if ($DefenderExclude) {
            $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')
            if (-not $admin) { Write-Warning '[venv] -DefenderExclude needs an elevated (admin) terminal; skipping exclusion.' }
            else {
                try { Add-MpPreference -ExclusionPath $venv -ErrorAction Stop; Write-Host "[venv] Defender exclusion added: $venv" }
                catch { Write-Warning "[venv] could not add Defender exclusion: $($_.Exception.Message)" }
            }
        }
        # build inside .venv so the pip build/unpack temp is covered by the exclusion too
        $buildTmp = Join-Path $venv 'pip-tmp'
        New-Item -ItemType Directory -Force $buildTmp | Out-Null
        Write-Host '[venv] installing requirements.txt'
        $envBak = @{ TMP = $env:TMP; TEMP = $env:TEMP; PYTHONUTF8 = $env:PYTHONUTF8 }
        $env:TMP = $buildTmp; $env:TEMP = $buildTmp; $env:PYTHONUTF8 = '1'
        try {
            & $venvPy -m pip install --quiet --disable-pip-version-check --upgrade pip | Out-Null
            & $venvPy -m pip install --disable-pip-version-check -r (Join-Path $root 'requirements.txt')
            $rc = $LASTEXITCODE
        } finally {
            $env:TMP = $envBak.TMP; $env:TEMP = $envBak.TEMP; $env:PYTHONUTF8 = $envBak.PYTHONUTF8
            Remove-Item -Recurse -Force $buildTmp -ErrorAction SilentlyContinue
        }
        if ($rc -eq 0) { Write-Host '[venv] ready: .venv\Scripts\python.exe' }
        else {
            Write-Warning '[venv] pip install failed. If impacket was blocked, Windows Defender quarantined it (HackTool:Python/Impacket).'
            Write-Warning '       Re-run elevated with: .\scripts\setup.ps1 -DefenderExclude'
            Write-Warning '       (adds .venv to Defender exclusions). pycryptodome-only features still work without impacket.'
        }
    } else {
        Write-Warning '[venv] creation failed.'
    }
}
