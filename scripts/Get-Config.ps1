# Load KEY=VALUE pairs from .env (project root). Returns a hashtable.
# Values starting with .\ or ./ are resolved relative to the file's folder.
param([string]$EnvPath = (Join-Path (Split-Path $PSScriptRoot -Parent) '.env'))

if (-not (Test-Path -LiteralPath $EnvPath)) { throw "Config not found: $EnvPath (copy .env.example to .env)" }
$base = Split-Path ([IO.Path]::GetFullPath($EnvPath)) -Parent

$cfg = @{}
foreach ($line in Get-Content -LiteralPath $EnvPath -Encoding UTF8) {
    $t = $line.Trim()
    if ($t -eq '' -or $t.StartsWith('#')) { continue }
    $i = $t.IndexOf('=')
    if ($i -lt 1) { continue }
    $v = $t.Substring($i + 1).Trim().Trim('"').Trim("'")
    if ($v -match '^\.[\\/]') { $v = [IO.Path]::GetFullPath((Join-Path $base $v.Substring(2))) }
    $cfg[$t.Substring(0, $i).Trim()] = $v
}
$cfg
