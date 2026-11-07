# Ekipa WoW - odinstalowanie: irm https://challenge.kubczi.pl/wow/uninstall.ps1 | iex
# Zatrzymuje uploader, usuwa autostart, addon i folder %LOCALAPPDATA%\EkipaWoW.
# Dane juz wyslane zostaja na stronie. Plik tylko ASCII (serwowany bez kodowania).

function Uninstall-Ekipa {
  $dir = Join-Path $env:LOCALAPPDATA 'EkipaWoW'
  try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*EkipaWoW\uploader.ps1*' } |
      ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null }
  } catch {}
  $lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Ekipa WoW Uploader.lnk'
  if (Test-Path $lnk) { Remove-Item $lnk -Force }
  $cfgPath = Join-Path $dir 'config.json'
  if (Test-Path $cfgPath) {
    try {
      $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json
      foreach ($f in @($cfg.flavors)) {
        $a = Join-Path $cfg.wow "$f\Interface\AddOns\Ekipa"
        if (Test-Path $a) { Remove-Item $a -Recurse -Force; Write-Host "Usuniety addon: $a" }
      }
    } catch {}
  }
  Start-Sleep -Seconds 1
  if (Test-Path $dir) { Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue }
  Write-Host 'Ekipa WoW odinstalowany. Mozesz zamknac to okno.' -ForegroundColor Green
}
Uninstall-Ekipa
