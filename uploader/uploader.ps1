# Ekipa WoW Uploader - dziala w tle (autostart Windows), bez okna.
# Co robi:
#  1. co 15 s sprawdza pliki World of Warcraft\_*_\WTF\Account\*\SavedVariables\Ekipa.lua
#  2. gdy plik sie zmienil (gra zapisuje go przy /reload, wylogowaniu i wyjsciu), pyta strone,
#     ktore zdarzenie ma jako ostatnie, i wysyla tylko nowsze,
#  3. co 3 h (i na starcie) sprawdza nowa wersje addonu i uploadera; addon podmienia,
#     gdy gra jest wylaczona.
# Konfiguracja: %LOCALAPPDATA%\EkipaWoW\config.json (token, adres strony, folder gry).
# Dziennik: %LOCALAPPDATA%\EkipaWoW\uploader.log
# Plik tylko ASCII (Windows PowerShell 5.1 czyta skrypty bez BOM jako ANSI).

$UploaderVersion = '1.0.0'
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

try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

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
  foreach ($l in $lines) {
    $m = $EventRx.Match($l)
    if ($m.Success -and [long]$m.Groups[2].Value -gt $last) {
      # tekst wysylamy tak, jak jest w pliku (z ucieczkami Lua) - strona sama go odkoduje
      $raw = $m.Groups[1].Value
      $events.Add('"' + $raw.Replace('\', '\\').Replace('"', '\"') + '"')
    }
  }
  if ($events.Count -eq 0) { return }
  $sent = 0
  for ($i = 0; $i -lt $events.Count; $i += 400) {
    $chunk = $events.GetRange($i, [Math]::Min(400, $events.Count - $i))
    $json = '{"konto":"' + $konto + '","uploader":"' + $UploaderVersion + '","events":[' + ($chunk -join ',') + ']}'
    $r = Invoke-Api 'POST' '/api/wow/ingest' $json
    $sent += [int]$r.added
  }
  Write-Log ("Wyslano {0} nowych zdarzen ({1}), konto {2}" -f $sent, $file.Directory.Parent.Name, $konto)
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
$failUntil = Get-Date
while ($true) {
  try {
    if ((Get-Date) -ge $nextUpdate) {
      $nextUpdate = (Get-Date).AddHours(3)
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
