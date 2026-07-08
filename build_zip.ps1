# Builds the installable mod ZIP with forward-slash entry paths
# (required by Godot's ZIP reader; PowerShell's Compress-Archive
# writes backslashes and breaks mod loading).
param(
    [string]$Version = "1.0.0"
)

$root = $PSScriptRoot
$src = Join-Path $root "mods-unpacked"
$dest = Join-Path $root ("Taylor-NodePins-{0}.zip" -f $Version)

if (Test-Path $dest) { Remove-Item $dest -Force -Confirm:$false }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($dest, 'Create')
Get-ChildItem $src -Recurse -File | ForEach-Object {
    $rel = "mods-unpacked/" + $_.FullName.Substring($src.Length + 1).Replace('\', '/')
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $rel) | Out-Null
}
$zip.Dispose()

Write-Output ("Built {0}" -f $dest)
