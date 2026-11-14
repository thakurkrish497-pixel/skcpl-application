$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
  $release = Join-Path $root 'build/windows/x64/runner/Release'
  if (!(Test-Path "$release/SKCPL.exe") -or !(Test-Path "$release/flutter_windows.dll") -or !(Test-Path "$release/data/flutter_assets")) {
    throw 'Expected x64 release bundle is missing. Run flutter build windows --release first.'
  }
  # App-local CRT deployment keeps the ZIP usable on a clean Windows computer.
  $vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
  if (!(Test-Path $vswhere)) { throw 'Visual Studio locator is missing.' }
  $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  if ($LASTEXITCODE -ne 0 -or !$vs) { throw 'Visual C++ tools were not found.' }
  $crt = Get-ChildItem "$vs/VC/Redist/MSVC/*/x64/Microsoft.VC*.CRT" -Directory | Sort-Object FullName -Descending | Select-Object -First 1
  if (!$crt) { throw 'Redistributable x64 Visual C++ runtime was not found.' }
  Copy-Item "$($crt.FullName)/*.dll" $release -Force
  foreach ($file in @('vcruntime140.dll', 'msvcp140.dll')) {
    if (!(Test-Path "$release/$file")) { throw "Missing runtime: $file" }
  }
  New-Item -ItemType Directory -Force dist | Out-Null
  @'
SKCPL ERP for Windows x64
Extract the entire ZIP before opening SKCPL.exe. Keep the data folder and all DLLs beside the EXE.
Sync pending entries before replacing an older installation; do not delete application data.
This portable build does not carry an Authenticode publisher signature.
'@ | Set-Content "$release/INSTALL.txt"
  Compress-Archive -Path "$release/*" -DestinationPath 'dist/SKCPL-Windows-x64.zip' -Force
  python scripts/release_manifest.py --platform windows-x64 --artifact dist/SKCPL-Windows-x64.zip
  if ($LASTEXITCODE -ne 0) { throw 'Release manifest creation failed.' }
} finally { Pop-Location }
