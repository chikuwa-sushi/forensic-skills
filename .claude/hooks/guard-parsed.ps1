# PreToolUse hook: block direct reads of PARSED_DIR. Use scripts/safe_read.ps1 instead.
# exit 2 = block (stderr is shown to Claude)
try {
    [Console]::InputEncoding = [Text.Encoding]::UTF8
    $in   = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $cfg  = & (Join-Path $PSScriptRoot '..\..\scripts\Get-Config.ps1')
    $root = [IO.Path]::GetFullPath($cfg.PARSED_DIR).TrimEnd('\')
} catch { exit 0 }

function Under([string]$p) {
    if (-not $p) { return $false }
    try { $f = [IO.Path]::GetFullPath($p) } catch { return $false }
    return $f.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)
}

$ti = $in.tool_input
$block = $false
switch ($in.tool_name) {
    'Read' { $block = Under $ti.file_path }
    'Grep' { $block = Under $ti.path }
    { $_ -in 'PowerShell', 'Bash' } {
        $c = [string]$ti.command
        $hitsDir = ($c.IndexOf($root, [StringComparison]::OrdinalIgnoreCase) -ge 0) -or ($c -match 'PARSED_DIR')
        $readVerb = '(?i)\b(Get-Content|gc|cat|type|more|less|head|tail|Import-Csv|ipcsv|Select-String|sls|findstr|grep|rg|ReadAllText|ReadAllLines|ReadLines|StreamReader|OpenText)\b'
        $block = $hitsDir -and ($c -match $readVerb)
    }
}

if ($block) {
    [Console]::Error.WriteLine("Blocked: direct read of PARSED_DIR is not allowed. Use scripts/safe_read.ps1 (see safe-read skill).")
    exit 2
}
exit 0
