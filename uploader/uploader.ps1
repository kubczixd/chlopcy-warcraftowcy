# Ekipa WoW Uploader - dziala w tle (autostart Windows), bez okna.
# Co robi:
#  1. co 15 s sprawdza pliki World of Warcraft\_*_\WTF\Account\*\SavedVariables\Ekipa.lua
#  2. gdy plik sie zmienil (gra zapisuje go przy /reload, wylogowaniu i wyjsciu), pyta strone,
#     ktore zdarzenie ma jako ostatnie, i wysyla tylko nowsze,
#  3. zrzuty mapy zrobione przez addon (ZRZUT): wycina sama mape, wysyla na strone (tlo mapy), usuwa zrzut,
#  4. na starcie, co 30 min i zaraz po wylaczeniu gry sprawdza nowa wersje addonu i uploadera;
#     addon podmienia, gdy gra jest wylaczona.
# Konfiguracja: %LOCALAPPDATA%\EkipaWoW\config.json (token, adres strony, folder gry).
# Dziennik: %LOCALAPPDATA%\EkipaWoW\uploader.log
# Plik tylko ASCII (Windows PowerShell 5.1 czyta skrypty bez BOM jako ANSI).

$UploaderVersion = '1.0.5'
$ErrorActionPreference = 'Stop'
$Dir = Join-Path $env:LOCALAPPDATA 'EkipaWoW'
$ConfigPath = Join-Path $Dir 'config.json'
$LogPath = Join-Path $Dir 'uploader.log'
$StatePath = Join-Path $Dir 'state.json'

function Write-Log([string]$msg) {
  try {
    if ((Test-Path $LogPath) -and (Get-Item $LogPath).Length -gt 512KB) {
      Move-Item $LogPath "$LogPath.old" -Force
    }
    Add-Content -Path $LogPath -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -Encoding UTF8
  } catch {}
}

# tylko jedna kopia naraz
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\EkipaWoWUploader', [ref]$created)
if (-not $created) { exit 0 }

# TLS: strona (Cloudflare) przyjmuje tylko TLS 1.3. Gdy .NET zostawia wybor systemowi (0 = SystemDefault), nic nie
# ruszamy; inaczej (stary domyslny Ssl3/Tls) dokladamy 1.2 i 1.3 (12288 - stary .NET nie zna nazwy Tls13).
# Samo wymuszenie Tls12 odcinalo TLS 1.3 i kazde polaczenie konczylo sie bledem 'bezpiecznego kanalu SSL/TLS'.
try {
  $sp = [Net.ServicePointManager]::SecurityProtocol
  if ([int]$sp -ne 0) {
    [Net.ServicePointManager]::SecurityProtocol = $sp -bor [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]12288
  }
} catch {}

if (-not (Test-Path $ConfigPath)) { Write-Log 'Brak config.json - uruchom instalacje jeszcze raz.'; exit 1 }
$cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$Base = $cfg.url.TrimEnd('/')
$Headers = @{ Authorization = "Bearer $($cfg.token)"; 'X-Ekipa-Uploader' = $UploaderVersion }

# stan: ostatnio wyslane pliki (czas zmiany) - zeby po restarcie nie czytac wszystkiego od nowa
$State = @{}
if (Test-Path $StatePath) {
  try { (Get-Content $StatePath -Raw | ConvertFrom-Json).psobject.Properties | ForEach-Object { $State[$_.Name] = $_.Value } } catch {}
}
function Save-State { try { $State | ConvertTo-Json | Set-Content $StatePath -Encoding UTF8 } catch {} }

function Invoke-Api([string]$method, [string]$path, [string]$json) {
  $p = @{ Uri = "$Base$path"; Method = $method; Headers = $Headers; UseBasicParsing = $true; TimeoutSec = 60 }
  if ($json) {
    $p.Body = [Text.Encoding]::UTF8.GetBytes($json)
    $p.ContentType = 'application/json; charset=utf-8'
  }
  $r = Invoke-WebRequest @p
  $text = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
  return ($text | ConvertFrom-Json)
}

function Get-SavedFiles {
  $root = $cfg.wow
  if (-not $root -or -not (Test-Path $root)) { return @() }
  return @(Get-ChildItem -Path (Join-Path $root '_*_\WTF\Account\*\SavedVariables\Ekipa.lua') -ErrorAction SilentlyContinue)
}

try { Add-Type -AssemblyName System.Drawing } catch {}

# --- zrzuty mapy ---------------------------------------------------------------
function Get-ShotFiles {
  $all = @()
  foreach ($f in @($cfg.flavors)) {
    $dir = Join-Path $cfg.wow "$f\Screenshots"
    if (Test-Path $dir) { $all += @(Get-ChildItem -Path $dir -Filter 'WoWScrnShot_*.jpg' -ErrorAction SilentlyContinue) }
  }
  return $all
}

function Send-MapShot($ev, $file) {
  $d = $ev.d
  $img = [Drawing.Image]::FromFile($file.FullName)
  $bmp = $null; $crop = $null; $ms = New-Object IO.MemoryStream
  try {
    $k = $img.Height / [double]$d.ekran[1]
    $r = @($d.r | ForEach-Object { [int]([double]$_ * $k) })
    $rect = New-Object Drawing.Rectangle $r[0], $r[1], $r[2], $r[3]
    $rect = [Drawing.Rectangle]::Intersect($rect, (New-Object Drawing.Rectangle 0, 0, $img.Width, $img.Height))
    if ($rect.Width -lt 50 -or $rect.Height -lt 50) { Write-Log "Zrzut mapy $($d.mapa): zly prostokat - pomijam"; return }
    $bmp = New-Object Drawing.Bitmap $img
    $crop = $bmp.Clone($rect, $bmp.PixelFormat)
    $enc = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
    $ep = New-Object Drawing.Imaging.EncoderParameters 1
    $ep.Param[0] = New-Object Drawing.Imaging.EncoderParameter ([Drawing.Imaging.Encoder]::Quality), ([long]88)
    $crop.Save($ms, $enc, $ep)
  } finally {
    if ($crop) { $crop.Dispose() }
    if ($bmp) { $bmp.Dispose() }
    $img.Dispose()
  }
  $b64 = [Convert]::ToBase64String($ms.ToArray())
  $json = '{"mapa":' + [int]$d.mapa + ',"odkryte":' + [int]$d.odkryte + ',"img":"' + $b64 + '"}'
  $res = Invoke-Api 'POST' '/api/wow/mapshot' $json
  Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
  Write-Log ("Mapa {0}: wyslano zrzut ({1} odkrytych, {2})" -f $d.mapa, $d.odkryte, $(if ($res.saved) { 'nowe tlo' } else { 'strona ma lepszy' }))
}

# Kod mapy narysowany przez addon w marginesie zrzutu (24 kwadraty: 20 bitow uiMapID + 4 bity sumy kontrolnej).
# -1 = brak kodu albo zly kod.
function Read-MapCode([string]$path, $kod, $ekran) {
  $img = $null
  try {
    $img = New-Object Drawing.Bitmap $path
    $k = $img.Height / [double]$ekran[1]
    $v = 0; $ones = 0; $chk = 0
    for ($i = 0; $i -lt 24; $i++) {
      $x = [int](([double]$kod.x + [double]$kod.s / 2) * $k)
      $y = [int](([double]$kod.y + [double]$kod.s * $i + [double]$kod.s / 2) * $k)
      if ($x -ge $img.Width -or $y -ge $img.Height) { return -1 }
      $c = $img.GetPixel($x, $y)
      $bit = [int](($c.R + $c.G + $c.B) -gt 384)
      if ($i -lt 20) { $v = $v -bor ($bit -shl $i); $ones += $bit } else { $chk = $chk -bor ($bit -shl ($i - 20)) }
    }
    if (($ones % 16) -ne $chk -or $v -eq 0) { return -1 }
    return $v
  } catch { return -1 } finally { if ($img) { $img.Dispose() } }
}

# ZRZUT z addonu -> plik zrzutu: po kodzie mapy w obrazie (addon >= 1.4.1), inaczej po czasie (zegar komputera)
function Send-MapShots($shots, $last) {
  if (-not $shots.Count) { return }
  $files = Get-ShotFiles
  $used = @{}
  $codes = @{}
  foreach ($ev in $shots) {
    try {
      $when = [DateTimeOffset]::FromUnixTimeSeconds([long]$ev.d.lokalnie).LocalDateTime
      if ($ev.d.kod) {
        $best = $null
        foreach ($f in ($files | Where-Object { -not $used[$_.FullName] -and [Math]::Abs(($_.LastWriteTime - $when).TotalSeconds) -le 30 } |
            Sort-Object { [Math]::Abs(($_.LastWriteTime - $when).TotalSeconds) })) {
          if (-not $codes.ContainsKey($f.FullName)) { $codes[$f.FullName] = Read-MapCode $f.FullName $ev.d.kod $ev.d.ekran }
          if ($codes[$f.FullName] -eq [int]$ev.d.mapa) { $best = $f; break }
        }
        if (-not $best) {
          if ([long]$ev.n -gt $last) { Write-Log "Mapa $($ev.d.mapa): nie znalazlem zrzutu z jej kodem" }
          continue
        }
        $used[$best.FullName] = $true
        Send-MapShot $ev $best
        continue
      }
      $best = $files | Where-Object { -not $used[$_.FullName] } |
        Sort-Object { [Math]::Abs(($_.LastWriteTime - $when).TotalSeconds) } | Select-Object -First 1
      if (-not $best -or [Math]::Abs(($best.LastWriteTime - $when).TotalSeconds) -gt 3) {
        if ([long]$ev.n -gt $last) { Write-Log "Mapa $($ev.d.mapa): nie znalazlem pliku zrzutu" }
        continue
      }
      $used[$best.FullName] = $true
      Send-MapShot $ev $best
    } catch { Write-Log "Mapa $($ev.d.mapa): blad zrzutu - $($_.Exception.Message)" }
  }
}

$EventRx = [regex]'^\s*"(\{\\"n\\":(\d+),.*\})",?\s*(--.*)?$'
$KontoRx = [regex]'\["konto"\]\s*=\s*"([0-9a-f]+)"'

function Send-File($file) {
  $lines = [IO.File]::ReadAllLines($file.FullName, [Text.Encoding]::UTF8)
  $konto = $null
  foreach ($l in $lines) { $m = $KontoRx.Match($l); if ($m.Success) { $konto = $m.Groups[1].Value; break } }
  if (-not $konto) { Write-Log "Brak id konta w $($file.FullName) - pomijam"; return }

  $info = Invoke-Api 'GET' "/api/wow/ingest?konto=$konto" $null
  $last = [long]$info.last_n
  $events = New-Object System.Collections.Generic.List[string]
  $shots = New-Object System.Collections.Generic.List[object]
  foreach ($l in $lines) {
    $m = $EventRx.Match($l)
    if (-not $m.Success) { continue }
    $raw = $m.Groups[1].Value
    # zrzuty mapy: wszystkie z pliku (wyslany zrzut jest usuwany z dysku, wiec drugi raz sie nie wysle;
    # tak nadrabiamy tez zrzuty, ktorych zdarzenia wyslal starszy uploader)
    if ($raw.Contains('\"e\":\"ZRZUT\"')) {
      try { $shots.Add((($raw -replace '\\(["\\])', '$1') | ConvertFrom-Json)) } catch {}
    }
    if ([long]$m.Groups[2].Value -gt $last) {
      # tekst wysylamy tak, jak jest w pliku (z ucieczkami Lua) - strona sama go odkoduje
      $events.Add('"' + $raw.Replace('\', '\\').Replace('"', '\"') + '"')
    }
  }
  if ($events.Count -eq 0) { Send-MapShots $shots $last; return }
  $sent = 0
  for ($i = 0; $i -lt $events.Count; $i += 400) {
    $chunk = $events.GetRange($i, [Math]::Min(400, $events.Count - $i))
    $json = '{"konto":"' + $konto + '","uploader":"' + $UploaderVersion + '","events":[' + ($chunk -join ',') + ']}'
    $r = Invoke-Api 'POST' '/api/wow/ingest' $json
    $sent += [int]$r.added
  }
  Write-Log ("Wyslano {0} nowych zdarzen ({1}), konto {2}" -f $sent, $file.Directory.Parent.Name, $konto)
  Send-MapShots $shots $last
}

# --- aktualizacje -------------------------------------------------------------
function Get-TocVersion([string]$toc) {
  if (-not (Test-Path $toc)) { return $null }
  foreach ($l in (Get-Content $toc)) { if ($l -match '^## Version:\s*(\S+)') { return $Matches[1] } }
  return $null
}

function Install-Addon($manifest, [string]$addonsDir) {
  $target = Join-Path $addonsDir 'Ekipa'
  New-Item -ItemType Directory -Force -Path $target | Out-Null
  foreach ($p in $manifest.files.psobject.Properties) {
    $path = Join-Path $target $p.Name
    [IO.File]::WriteAllText($path, $p.Value, (New-Object Text.UTF8Encoding($false)))
  }
}

function Update-All {
  $manifest = Invoke-Api 'GET' '/wow/addon.json' $null
  # addon: tylko gdy gra jest wylaczona (gra trzyma pliki addonu w pamieci, podmiana w trakcie nic nie da)
  if (-not (Get-Process | Where-Object { $_.ProcessName -like 'Wow*' })) {
    $root = $cfg.wow
    $flavors = @()
    if ($cfg.flavors) { $flavors = @($cfg.flavors) }
    foreach ($f in $flavors) {
      $addons = Join-Path $root "$f\Interface\AddOns"
      $cur = Get-TocVersion (Join-Path $addons 'Ekipa\Ekipa.toc')
      if ($cur -ne $manifest.version) {
        Install-Addon $manifest $addons
        Write-Log "Addon zaktualizowany do $($manifest.version) ($f)"
      }
    }
  }
  # uploader: nowa wersja -> pobierz, uruchom nowa kopie, zakoncz te
  if ($manifest.uploaderVersion -and $manifest.uploaderVersion -ne $UploaderVersion) {
    $r = Invoke-WebRequest -Uri "$Base/wow/uploader.ps1" -UseBasicParsing -TimeoutSec 60
    $text = [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
    if ($text -match "UploaderVersion = '([^']+)'") {
      $self = Join-Path $Dir 'uploader.ps1'
      [IO.File]::WriteAllText($self, $text, (New-Object Text.UTF8Encoding($true)))
      Write-Log "Uploader zaktualizowany do $($Matches[1]) - restart"
      $mutex.ReleaseMutex()
      Start-Process -FilePath (Join-Path $env:windir 'System32\conhost.exe') -WindowStyle Hidden `
        -ArgumentList "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$self`""
      exit 0
    }
  }
}

# --- petla glowna -------------------------------------------------------------
Write-Log "Start uploadera $UploaderVersion (gra: $($cfg.wow))"
$nextUpdate = Get-Date
$gameWasOn = $false
$failUntil = Get-Date
while ($true) {
  try {
    # gra wlasnie sie wylaczyla -> od razu sprawdz aktualizacje (addon mozna podmienic tylko przy wylaczonej grze)
    $gameOn = [bool](Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'Wow*' })
    if ($gameWasOn -and -not $gameOn) { $nextUpdate = Get-Date }
    $gameWasOn = $gameOn
    if ((Get-Date) -ge $nextUpdate) {
      $nextUpdate = (Get-Date).AddMinutes(30)
      try { Update-All } catch { Write-Log "Aktualizacja nieudana: $($_.Exception.Message)" }
    }
    if ((Get-Date) -ge $failUntil) {
      foreach ($f in (Get-SavedFiles)) {
        $stamp = $f.LastWriteTimeUtc.Ticks.ToString()
        if ($State[$f.FullName] -ne $stamp) {
          # gra moze jeszcze pisac plik - poczekaj, az czas zmiany bedzie mial co najmniej 3 s
          if (((Get-Date).ToUniversalTime() - $f.LastWriteTimeUtc).TotalSeconds -lt 3) { continue }
          Send-File $f
          $State[$f.FullName] = $stamp
          Save-State
        }
      }
    }
  } catch {
    $msg = $_.Exception.Message
    Write-Log "Blad: $msg (ponowie za 2 min)"
    $failUntil = (Get-Date).AddMinutes(2)
  }
  Start-Sleep -Seconds 15
}
