# Chłopcy Warcraftowcy – addon Ekipa

Addon do **WoW Forever**, który zbiera statystyki postaci ekipy, i uploader, który wysyła je na
**challenge.kubczi.pl** (zakładka Gry → WoW).

👉 **Dla graczy: [INSTRUKCJA.md](INSTRUKCJA.md)** – instalacja krok po kroku.

Wzorowane na pomysłach z LUDOS-on (gildyjny addon do Forever): odczyt danych bez combat logu (w Forever jest
zablokowany), omijanie wartości ukrytych przez grę, /played bez spamu na czacie. Bez wymiany danych przez gildię –
każdy wysyła swoje dane sam.

## Jak to działa

```
WoW (addon Ekipa) ──/reload, wylogowanie──▶ WTF\Account\<KONTO>\SavedVariables\Ekipa.lua
                                                   │  uploader (PowerShell w tle, autostart)
                                                   ▼  wysyła tylko nowe zdarzenia
                                   POST challenge.kubczi.pl/api/wow/ingest  (token gracza)
```

- **WoW nie pozwala addonom na internet.** Addon może tylko zapisać plik (gra robi to przy `/reload`,
  wylogowaniu i wyjściu), dlatego potrzebny jest uploader na komputerze.
- Każde zdarzenie to jedna linia JSON w `EkipaLog`, numerowana (`n`) w obrębie konta WoW (`EkipaDB.meta.konto`,
  losowe id). Uploader pyta stronę o ostatni numer i wysyła tylko nowsze – wysyłka jest idempotentna.
- Plik trzyma najwyżej ~30 000 ostatnich zdarzeń (starsze strona już ma).

## Zdarzenia

| Kod | Kiedy | Dane |
|---|---|---|
| `LOGIN` / `LOGOUT` | wejście / wyjście z gry (`/reload` nie kończy sesji) | poziom, strefa, imię, klasa, rasa… |
| `STAN` | przy każdym zapisie gry | pełny stan: poziom, xp, złoto, /played, gildia, HK, liczniki całości i sesji |
| `LVL` | awans | poziom, /played w chwili awansu |
| `QUEST` | oddany quest | id, nazwa, exp, złoto |
| `MOB` | zabity mob (`PARTY_KILL` + komunikat o expie) | nazwa, NPC id, exp, czy mój cios |
| `SMIERC` | śmierć (Forever: Death Recap, Classic: combat log) | zabójca, czar, obrażenia, poziom, strefa |
| `LOOT` | przedmiot niebieski+ | id, nazwa, jakość, ilość |
| `PVP_ZAB` / `PVP_SMIERC` | zabity gracz / śmierć od gracza (poza BG) | nick, poziom, klasa, rasa, gildia, strefa |
| `STREFA`, `BOSS` | zmiana strefy, koniec walki z bossem | |
| `HISTORIA` | raz na postać (15 s po pierwszym wejściu) i `/ekipa historia` | dane wstecz: ukończone questy, statystyki postaci, osiągnięcia z datami, profesje, liczniki addonu w tej chwili |

`STAN.wszech` – przy każdym zapisie najważniejsze statystyki od początku gry (ID: 60 śmierci, 1197 zabici, 98 questy,
328/333/326 złoto, 1501 śmierci PvP, 349 loty, 932 lochy) + liczba ukończonych questów. Jeśli gra ich nie podaje,
strona liczy: dane wstecz + to, co addon policzył po ich odczycie (bez liczenia dwa razy), a w ostateczności od instalacji.
`/ekipa sonda` wypisuje na czacie, co z tego gra faktycznie udostępnia.

Liczniki (`staty` w `STAN`): moby, śmierci, questy, exp (moby / questy / inne), złoto (+/−/loot/questy), PvP,
bossy, awanse, loot wg jakości, naprawy, czas AFK. `STAN.sesja` = te same liczniki dla bieżącej sesji.

## Struktura

```
addon/Ekipa/      addon (Lua, tylko ASCII – czcionki WoW i PowerShell 5.1)
  Ekipa.toc       ## Interface: 16001 (Forever), 11509, 20506, 120105
  Json.lua        koder JSON + obsługa wartości ukrytych (issecretvalue)
  Core.lua        baza, sesje, dziennik, /played, przypomnienie o /reload, komendy /ekipa
  Track.lua       co zbieramy (exp, poziomy, questy, złoto, loot, moby, śmierci, PvP, strefy, bossy, AFK)
  History.lua     dane wstecz (HISTORIA, STAN.wszech) i /ekipa sonda
uploader/
  install.ps1     instalacja (strona dokleja token: /api/wow/install.ps1?t=…)
  uploader.ps1    działa w tle; wysyłka + automatyczne aktualizacje addonu i siebie (tylko ASCII)
  uninstall.ps1   odinstalowanie (tylko ASCII)
tools/
  pack.mjs        wydanie do public/wow strony (addon.json, Ekipa.zip, skrypty)
  test/sim.lua    symulacja addonu poza grą (atrapy API WoW) → plik Ekipa.lua w formacie gry
```

## Wydanie nowej wersji

1. Podbij `## Version:` w `addon/Ekipa/Ekipa.toc` (i/lub `$UploaderVersion` w `uploader/uploader.ps1`).
2. `node tools/pack.mjs ../ekipa-challange/public/wow`
3. Commit + deploy strony. Uploadery u graczy pobiorą nowy addon w ciągu ~3 h (gdy gra jest wyłączona).

## Test

```bash
lua5.1 tools/test/sim.lua addon/Ekipa /tmp/Ekipa.lua   # symulacja: logowanie, mob, quest, loot, awans, śmierć, /reload
```

Plik wynikowy można wgrać ręcznie na stronie (zakładka WoW → Inne opcje) albo na lokalnym `npm run dev`.
