<#
Collect artifacts from a mounted drive with CDIR-C.
- Copies CDIR-C to a temp run folder and generates cdir.ini from config\cdir.ini.template
- Original tools\cdir-collector is never modified
- Verifies the collected SYSTEM hive matches the target drive
- Writes <collected>_cdir.ini and <collected>_hashes.csv next to the collected folder
  .\scripts\Invoke-Cdirc.ps1 -Drive F:
#>
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z]:?\\?$')][string]$Drive,
    [string]$Root   # passed to Invoke-LogicalCollect.ps1 when the drive is not NTFS
)
$ErrorActionPreference = 'Stop'

$proj   = Split-Path $PSScriptRoot -Parent
$cfg    = & (Join-Path $PSScriptRoot 'Get-Config.ps1')
$target = $Drive.Substring(0, 1).ToUpper() + ':\'
if (-not (Test-Path -LiteralPath $target)) { throw "Drive not found: $target" }

# NTFS check (CDIR-C reads NTFS raw; logical images such as .ad1 are not NTFS volumes)
$fs = try { ([IO.DriveInfo]::new($target)).DriveFormat } catch { 'unknown' }
if ($fs -ne 'NTFS') {
    "ntfs=False fs=$fs mode=logical"
    $p = @{ Drive = $Drive }; if ($Root) { $p.Root = $Root }
    & (Join-Path $PSScriptRoot 'Invoke-LogicalCollect.ps1') @p
    exit $LASTEXITCODE
}
"ntfs=True"

$sysHive = Join-Path $target 'Windows\System32\config\SYSTEM'
if (-not (Test-Path -LiteralPath $sysHive)) { throw "SYSTEM hive not found: $sysHive" }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')
if (-not $admin) { throw 'Administrator privileges required. Run from an elevated terminal.' }
if (-not (Test-Path -LiteralPath $cfg.CDIRC_PATH)) { throw "CDIR-C not found: $($cfg.CDIRC_PATH) (run scripts\setup.ps1)" }

$out = [IO.Path]::GetFullPath($cfg.COLLECT_DIR).TrimEnd('\')
New-Item -ItemType Directory -Force $out | Out-Null
$run = Join-Path $out ('_run\' + (Get-Date -Format yyyyMMddHHmmss))
New-Item -ItemType Directory -Force $run | Out-Null

# copy binaries (without ini / winpmem)
Get-ChildItem -LiteralPath (Split-Path $cfg.CDIRC_PATH) -File |
    Where-Object { $_.Name -notlike 'winpmem*' -and $_.Name -notlike 'cdir.*' } |
    Copy-Item -Destination $run

# generate cdir.ini (ANSI, CRLF, no trailing spaces)
$ini = (Get-Content -LiteralPath (Join-Path $proj 'config\cdir.ini.template') -Raw -Encoding UTF8)
$ini = $ini.Replace('{TARGET}', $target).Replace('{OUTPUT}', $out)
$ini = (($ini -split "\r?\n") | ForEach-Object { $_.TrimEnd() }) -join "`r`n"
$runIni = Join-Path $run 'cdir.ini'
[IO.File]::WriteAllText($runIni, $ini, [Text.Encoding]::Default)

# run (feed newlines for the final "Press Enter" prompt)
$before = @(Get-ChildItem -LiteralPath $out -Directory | ForEach-Object { $_.FullName })
Push-Location $run
try { "`r`n`r`n" | & (Join-Path $run (Split-Path $cfg.CDIRC_PATH -Leaf)) } finally { Pop-Location }

$col = Get-ChildItem -LiteralPath $out -Directory |
    Where-Object { $_.Name -ne '_run' -and $before -notcontains $_.FullName } |
    Sort-Object LastWriteTime | Select-Object -Last 1
if (-not $col) { throw "Collected folder not found under $out. Run folder kept: $run" }

Copy-Item -LiteralPath $runIni -Destination "$($col.FullName)_cdir.ini"
Remove-Item -LiteralPath $run -Recurse -Force

# verify origin
$colSys = Get-ChildItem -LiteralPath $col.FullName -Recurse -File -Force -Filter 'SYSTEM' |
    Where-Object { $_.FullName -notmatch 'Windows\.old' } | Select-Object -First 1
$match = $false
if ($colSys) { $match = (Get-FileHash -LiteralPath $colSys.FullName).Hash -eq (Get-FileHash -LiteralPath $sysHive).Hash }

# hashes
Get-ChildItem -LiteralPath $col.FullName -Recurse -File -Force | Get-FileHash -Algorithm SHA256 |
    Export-Csv -LiteralPath "$($col.FullName)_hashes.csv" -NoTypeInformation -Encoding UTF8

"collected=$($col.FullName)"
"system_hive_found=$([bool]$colSys) system_hash_match=$match"
