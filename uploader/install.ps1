# Ekipa WoW - instalacja addonu i uploadera.
# Uruchamiane komenda ze strony (zakladka Gry -> WoW -> "Zainstaluj addon"):
#   irm "https://challenge.kubczi.pl/api/wow/install.ps1?t=TOKEN" | iex
# Strona dopisuje na poczatku $EkipaToken i $EkipaUrl. Bez 'exit' (zamknalby okno PowerShella).

function Install-Ekipa {
  $ErrorActionPreference = 'Stop'
  try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
  $url = if ($EkipaUrl) { $EkipaUrl } else { 'https://challenge.kubczi.pl' }
  $token = $EkipaToken

  function Say([string]$t, [string]$color = 'Gray') { Write-Host $t -ForegroundColor $color }
  function Get-Json([string]$u, $headers) {
    $p = @{ Uri = $u; UseBasicParsing = $true; TimeoutSec = 60 }
    if ($headers) { $p.Headers = $headers }
    $r = Invoke-WebRequest @p
    return ([Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray()) | ConvertFrom-Json)
  }

  Write-Host ''
  Say '=== Ekipa WoW - instalacja ===' 'Yellow'
  if (-not $token) { Say 'Brak tokenu. Skopiuj komendę jeszcze raz ze strony (Gry -> WoW -> Zainstaluj addon).' 'Red'; return }

  # 1. kto to
  try {
    $me = Get-Json "$url/api/wow/ingest/me" @{ Authorization = "Bearer $token" }
  } catch {
    Say 'Strona nie przyjęła tokenu albo nie ma internetu. Skopiuj komendę jeszcze raz ze strony.' 'Red'
    Say $_.Exception.Message 'DarkGray'
    return
  }
  Say ("Cześć {0}! Instaluję addon i uploader." -f $me.player) 'Green'

  # 2. folder World of Warcraft
  $cands = New-Object System.Collections.Generic.List[string]
  foreach ($key in 'HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft', 'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft') {
    try {
      $p = (Get-ItemProperty -Path $key -ErrorAction Stop).InstallPath
      if ($p) { $cands.Add($p.TrimEnd('\')) }
    } catch {}
  }
  try {
    $db = Join-Path $env:ProgramData 'Battle.net\Agent\product.db'
    if (Test-Path $db) {
      $txt = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($db))
      foreach ($m in [regex]::Matches($txt, '[A-Za-z]:[\\/][ -~]*?World of Warcraft')) { $cands.Add($m.Value.Replace('/', '\')) }
    }
  } catch {}
  foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
    foreach ($sub in 'Program Files (x86)\World of Warcraft', 'Program Files\World of Warcraft', 'World of Warcraft', 'Games\World of Warcraft', 'Gry\World of Warcraft', 'Blizzard\World of Warcraft', 'Battle.net\World of Warcraft') {
      $cands.Add((Join-Path $d.Root $sub))
    }
  }
  $root = $null
  foreach ($c in $cands) {
    $c = $c.TrimEnd('\')
    if ((Split-Path $c -Leaf) -match '^_.+_$') { $c = Split-Path $c -Parent } # np. ...\World of Warcraft\_retail_
    if ((Test-Path $c) -and (Get-ChildItem -Path $c -Directory -Filter '_*_' -ErrorAction SilentlyContinue)) { $root = $c; break }
  }
  while (-not $root) {
    Say 'Nie znalazłem folderu World of Warcraft.' 'Yellow'
    Say 'Otwórz Battle.net -> World of Warcraft -> koło zębate obok "Graj" -> "Pokaż w Eksploratorze",' 'Gray'
    Say 'skopiuj ścieżkę z paska adresu (np. D:\Gry\World of Warcraft) i wklej tutaj.' 'Gray'
    $c = (Read-Host 'Folder gry').Trim().Trim('"').TrimEnd('\')
    if ((Split-Path $c -Leaf) -match '^_.+_$') { $c = Split-Path $c -Parent }
    if ($c -and (Test-Path $c) -and (Get-ChildItem -Path $c -Directory -Filter '_*_' -ErrorAction SilentlyContinue)) { $root = $c }
  }
  Say "Gra: $root" 'Gray'

  # 3. wersja gry (_forever_, _classic_era_ ...)
  $all = @(Get-ChildItem -Path $root -Directory -Filter '_*_' | ForEach-Object { $_.Name })
  $flavors = @($all | Where-Object { $_ -like '*forever*' })
  if ($flavors.Count -eq 0) {
    Say 'Nie widzę folderu WoW Forever. Znalezione wersje gry:' 'Yellow'
    for ($i = 0; $i -lt $all.Count; $i++) { Say ("  {0}. {1}" -f ($i + 1), $all[$i]) }
    while ($flavors.Count -eq 0) {
      $n = Read-Host 'Wpisz numer wersji, w którą grasz'
      $idx = 0
      if ([int]::TryParse($n, [ref]$idx) -and $idx -ge 1 -and $idx -le $all.Count) { $flavors = @($all[$idx - 1]) }
    }
  }

  # 4. addon
  $manifest = Get-Json "$url/wow/addon.json" $null
  foreach ($f in $flavors) {
    $target = Join-Path $root "$f\Interface\AddOns\Ekipa"
    New-Item -ItemType Directory -Force -Path $target | Out-Null
    foreach ($p in $manifest.files.psobject.Properties) {
      [IO.File]::WriteAllText((Join-Path $target $p.Name), $p.Value, (New-Object Text.UTF8Encoding($false)))
    }
    Say "Addon $($manifest.version) zainstalowany: $target" 'Green'
  }

  # 5. uploader
  $dir = Join-Path $env:LOCALAPPDATA 'EkipaWoW'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  # stara kopia (ponowna instalacja) - zatrzymaj
  try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*EkipaWoW\uploader.ps1*' } |
      ForEach-Object { Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null }
  } catch {}
  $cfg = [ordered]@{ token = $token; url = $url; wow = $root; flavors = $flavors; player = $me.player }
  ($cfg | ConvertTo-Json) | Set-Content -Path (Join-Path $dir 'config.json') -Encoding UTF8
  $r = Invoke-WebRequest -Uri "$url/wow/uploader.ps1" -UseBasicParsing -TimeoutSec 60
  $script = Join-Path $dir 'uploader.ps1'
  [IO.File]::WriteAllText($script, [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray()), (New-Object Text.UTF8Encoding($true)))

  # 6. autostart (skrot w folderze Autostart) i start teraz - bez okna
  $conhost = Join-Path $env:windir 'System32\conhost.exe'
  $argLine = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$script`""
  $lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Ekipa WoW Uploader.lnk'
  $sh = New-Object -ComObject WScript.Shell
  $s = $sh.CreateShortcut($lnk)
  $s.TargetPath = $conhost
  $s.Arguments = $argLine
  $s.WorkingDirectory = $dir
  $s.WindowStyle = 7
  $s.Description = 'Wysyla statystyki z WoW na challenge.kubczi.pl'
  $s.Save()
  Start-Process -FilePath $conhost -ArgumentList $argLine -WindowStyle Hidden
  Say 'Uploader działa w tle i będzie się uruchamiał sam razem z Windowsem.' 'Green'

  Write-Host ''
  Say '=== Gotowe! ===' 'Yellow'
  Say '1. Uruchom WoW. Na ekranie wyboru postaci kliknij "AddOns" (lewy dolny róg)' 'White'
  Say '   i upewnij się, że "Ekipa Challenge" jest zaznaczony.' 'White'
  Say '2. W grze rób od czasu do czasu /reload (np. w locie) - wtedy dane trafiają na stronę.' 'White'
  Say '3. To okno możesz zamknąć.' 'White'
  Write-Host ''
}
Install-Ekipa
