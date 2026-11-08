<#
Collect artifacts by file copy (for logical images such as .ad1 / non-NTFS mounts).
- Locates the Windows root (folder containing Windows\System32\config\SYSTEM)
- Copies artifacts with robocopy (keeps timestamps, long-path safe), preserving relative paths
- Verifies source/copy SHA256
  .\scripts\Invoke-LogicalCollect.ps1 -Drive F:
  .\scripts\Invoke-LogicalCollect.ps1 -Drive F: -Root 'F:\E___OS [NTFS]\[root]'
Output: <COLLECT_DIR>\<COMPUTERNAME>_<drive>_<timestamp>_logical
        _manifest.csv (found/missing), _hashes.csv (source/copy SHA256), _robocopy.log
Exit: 0 ok / 3 multiple roots found (use -Root)
#>
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z]:?\\?$')][string]$Drive,
    [string]$Root,
    [int]$Depth = 3
)
$ErrorActionPreference = 'Stop'
$cfg    = & (Join-Path $PSScriptRoot 'Get-Config.ps1')
$letter = $Drive.Substring(0, 1).ToUpper()
$target = "${letter}:\"
$sysRel = 'Windows\System32\config\SYSTEM'

# 1. locate Windows root
if (-not $Root) {
    $dirs = @(Get-Item -LiteralPath $target -Force) +
            @(Get-ChildItem -LiteralPath $target -Directory -Force -Recurse -Depth ($Depth - 1) -ErrorAction SilentlyContinue)
    $cand = @($dirs | Where-Object { $_.Name -ne 'Windows.old' -and (Test-Path -LiteralPath (Join-Path $_.FullName $sysRel)) } |
              ForEach-Object { $_.FullName })
    if ($cand.Count -eq 0) { throw "Windows root not found within depth $Depth under $target. Use -Root." }
    if ($cand.Count -gt 1) { 'root_candidates:'; $cand | ForEach-Object { "  $_" }; exit 3 }
    $Root = $cand[0]
}
$Root = $Root.TrimEnd('\'); if ($Root -match '^[A-Za-z]:$') { $Root += '\' }
if (-not (Test-Path -LiteralPath (Join-Path $Root $sysRel))) { throw "SYSTEM hive not found under root: $Root" }
"root=$Root"

# 2. output folder
$out = [IO.Path]::GetFullPath($cfg.COLLECT_DIR).TrimEnd('\')
$col = Join-Path $out ('{0}_{1}_{2}_logical' -f $env:COMPUTERNAME, $letter, (Get-Date -Format yyyyMMddHHmmss))
New-Item -ItemType Directory -Force $col | Out-Null
$log = "${col}_robocopy.log"

# 3. targets (Dir: relative to root, Files: robocopy filters)
$targets = New-Object System.Collections.Generic.List[object]
function Add-T([string]$Name, [string]$Dir, [string[]]$Files, [bool]$Recurse = $false) {
    $targets.Add([pscustomobject]@{ Name = $Name; Dir = $Dir; Files = $Files; Recurse = $Recurse })
}
Add-T 'MFT'      ''                             @('$MFT')
Add-T 'UsnJrnl'  '$Extend'                      @('$UsnJrnl')
Add-T 'Registry' 'Windows\System32\config'      @('SYSTEM', 'SYSTEM.LOG*', 'SOFTWARE', 'SOFTWARE.LOG*', 'SAM', 'SAM.LOG*', 'SECURITY', 'SECURITY.LOG*', 'DEFAULT', 'DEFAULT.LOG*')
Add-T 'Amcache'  'Windows\appcompat\Programs'   @('Amcache.hve', 'Amcache.hve.LOG*')
Add-T 'SRUM'     'Windows\System32\sru'         @('*')
Add-T 'Prefetch' 'Windows\Prefetch'             @('*.pf')
Add-T 'EventLog' 'Windows\System32\winevt\Logs' @('*.evtx')

$users = @(Get-ChildItem -LiteralPath (Join-Path $Root 'Users') -Directory -Force -ErrorAction SilentlyContinue |
           Where-Object { (Test-Path -LiteralPath (Join-Path $_.FullName 'NTUSER.DAT')) -or (Test-Path -LiteralPath (Join-Path $_.FullName 'AppData')) })
foreach ($u in $users) {
    $b = "Users\$($u.Name)"
    Add-T "NTUSER($($u.Name))"   $b                                              @('NTUSER.DAT', 'NTUSER.DAT.LOG*')
    Add-T "UsrClass($($u.Name))" "$b\AppData\Local\Microsoft\Windows"            @('UsrClass.dat', 'UsrClass.dat.LOG*')
    Add-T "WebCache($($u.Name))" "$b\AppData\Local\Microsoft\Windows\WebCache"   @('*')
    Add-T "Edge($($u.Name))"     "$b\AppData\Local\Microsoft\Edge\User Data"     @('History', 'History-journal') $true
    Add-T "Chrome($($u.Name))"   "$b\AppData\Local\Google\Chrome\User Data"      @('History', 'History-journal') $true
    Add-T "Firefox($($u.Name))"  "$b\AppData\Roaming\Mozilla\Firefox\Profiles"   @('places.sqlite*', 'cookies.sqlite*') $true
}

# 4. copy
# robocopy first; some virtual file systems (e.g. FTK Imager mounts) fail directory scans (ERROR 1359),
# so fall back to PowerShell copy and restore timestamps.
function Get-SourceFiles($src, $t) {
    # *.FileSlack: slack space files exposed by FTK Imager mounts (not artifacts)
    @(Get-ChildItem -LiteralPath $src -File -Force -Recurse:$t.Recurse -ErrorAction SilentlyContinue |
      Where-Object { $n = $_.Name; $n -notlike '*.FileSlack' -and @($t.Files | Where-Object { $n -like $_ }).Count -gt 0 })
}
function Copy-Fallback($src, $dst, $files) {
    foreach ($f in $files) {
        $to = Join-Path $dst $f.FullName.Substring($src.TrimEnd('\').Length + 1)
        New-Item -ItemType Directory -Force (Split-Path $to) | Out-Null
        Copy-Item -LiteralPath $f.FullName -Destination $to -Force
        $c = Get-Item -LiteralPath $to -Force
        $c.CreationTimeUtc = $f.CreationTimeUtc; $c.LastWriteTimeUtc = $f.LastWriteTimeUtc; $c.LastAccessTimeUtc = $f.LastAccessTimeUtc
    }
}

$manifest = New-Object System.Collections.Generic.List[object]
foreach ($t in $targets) {
    $src = if ($t.Dir) { Join-Path $Root $t.Dir } else { $Root }
    $dst = if ($t.Dir) { Join-Path $col $t.Dir } else { $col }
    $status = 'missing'; $count = 0; $dups = 0; $zero = 0; $method = ''
    if (Test-Path -LiteralPath $src) {
        $srcFiles = Get-SourceFiles $src $t
        # same name listed twice in one folder (seen on .ad1 mounts); only one is reachable by path
        $dups = @($srcFiles | Group-Object { $_.FullName.ToLower() } | Where-Object { $_.Count -gt 1 }).Count
        $zero = @($srcFiles | Where-Object { $_.Length -eq 0 } | ForEach-Object { $_.FullName.ToLower() } | Sort-Object -Unique).Count
        if ($srcFiles.Count -gt 0 -and $dups -gt 0) {
            # robocopy writes 8.3 short-name junk files for duplicated entries; copy one file per name instead
            $uniq = @($srcFiles | Group-Object { $_.FullName.ToLower() } | ForEach-Object { $_.Group | Sort-Object Length -Descending | Select-Object -First 1 })
            Copy-Fallback $src $dst $uniq
            $method = 'powershell(dup)'
            $count = @(Get-ChildItem -LiteralPath $dst -File -Force -Recurse:$t.Recurse -ErrorAction SilentlyContinue).Count
            $status = if ($count -gt 0) { 'collected' } else { 'error' }
        }
        elseif ($srcFiles.Count -gt 0) {
            $opt =@('/COPY:DAT', '/DCOPY:T', '/R:1', '/W:1', '/XJ', '/NP', '/NJH', '/NJS', '/NDL', '/XF', '*.FileSlack', "/LOG+:$log")
            if ($t.Recurse) { $opt += '/S' }
            & robocopy $src $dst @($t.Files) @opt | Out-Null
            $method = 'robocopy'
            if ($LASTEXITCODE -ge 8) { Copy-Fallback $src $dst $srcFiles; $method = 'powershell' }
            else {
                # files robocopy silently skipped
                $base = $src.TrimEnd('\').Length + 1
                $miss = @($srcFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $dst $_.FullName.Substring($base))) })
                if ($miss.Count -gt 0) { Copy-Fallback $src $dst $miss; $method = "robocopy+powershell($($miss.Count))" }
            }
            $count = @(Get-ChildItem -LiteralPath $dst -File -Force -Recurse:$t.Recurse -ErrorAction SilentlyContinue).Count
            $status = if ($count -gt 0) { 'collected' } else { 'error' }
        }
    }
    $manifest.Add([pscustomobject]@{ Artifact = $t.Name; Source = $src; Status = $status; Files = $count; DuplicateNames = $dups; ZeroByte = $zero; Method = $method })
}

# $UsnJrnl:$J is an alternate data stream; check it survived the copy
$usnCopy = Join-Path $col '$Extend\$UsnJrnl'
$jStream = 'n/a'
if (Test-Path -LiteralPath $usnCopy) { $jStream = [bool](Get-Item -LiteralPath $usnCopy -Stream '$J' -ErrorAction SilentlyContinue) }

# 5. hashes (source vs copy)
$hashes = foreach ($f in @(Get-ChildItem -LiteralPath $col -Recurse -File -Force)) {
    $rel = $f.FullName.Substring($col.Length + 1)
    $h1 = try { (Get-FileHash -LiteralPath (Join-Path $Root $rel) -Algorithm SHA256).Hash } catch { '' }
    $h2 = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
    [pscustomobject]@{ RelativePath = $rel; Size = $f.Length; SourceSHA256 = $h1; CopySHA256 = $h2; Match = ($h1 -eq $h2) }
}
$manifest | Export-Csv -LiteralPath "${col}_manifest.csv" -NoTypeInformation -Encoding UTF8
$hashes   | Export-Csv -LiteralPath "${col}_hashes.csv"   -NoTypeInformation -Encoding UTF8

"collected=$col"
$manifest | ForEach-Object {
    $line = '{0,-24} {1,-10} files={2} {3}' -f $_.Artifact, $_.Status, $_.Files, $_.Method
    if ($_.DuplicateNames -gt 0) { $line += " WARN duplicate_names=$($_.DuplicateNames)" }
    if ($_.ZeroByte -gt 0) { $line += " WARN zero_byte=$($_.ZeroByte)" }
    $line
}
"usnjrnl_J_stream=$jStream"
"hash_mismatch=$(@($hashes | Where-Object { -not $_.Match }).Count)"
exit 0
