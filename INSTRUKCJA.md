# 🐉 Addon Ekipa – instrukcja krok po kroku

Dzięki temu na stronie **challenge.kubczi.pl** (Gry → WoW) same pojawiają się Twój poziom, czas gry, złoto,
śmierci, zabite moby, questy, loot i PvP. Instalujesz **raz** (ok. 2 minuty), potem nic nie musisz pamiętać.

> Potrzebujesz: komputer z Windowsem, na którym grasz w WoW Forever, i konto na challenge.kubczi.pl.

---

## Krok 1. Skopiuj swoją komendę ze strony

1. Wejdź na **challenge.kubczi.pl** i zaloguj się.
2. Kliknij **🎮 Gry**, a u góry zakładkę **WoW**.
3. Kliknij przycisk **🧩 Zainstaluj addon**.
4. Kliknij **Pokaż moją komendę**, a potem **📋 Kopiuj**.

Komenda wygląda mniej więcej tak (Twoja ma inne literki na końcu – to Twój osobisty klucz):

```
irm "https://challenge.kubczi.pl/api/wow/install.ps1?t=Ab12Cd34..." | iex
```

⚠️ Nie wysyłaj tej komendy innym – dane z ich gry trafiłyby na Twoje konto.

## Krok 2. Wklej komendę w PowerShell

1. **Zamknij WoW**, jeśli jest włączony.
2. Kliknij **Start** (logo Windows w lewym dolnym rogu) i wpisz na klawiaturze: **PowerShell**.
3. Kliknij **Windows PowerShell** (niebieska ikonka). Otworzy się niebieskie albo czarne okno z tekstem.
   *Nie* wybieraj „Uruchom jako administrator” – nie jest potrzebne.
4. Kliknij w to okno **prawym przyciskiem myszy** – komenda sama się wklei. (Albo naciśnij **Ctrl + V**.)
5. Naciśnij **Enter**.

Skrypt sam:
- znajdzie folder z grą,
- wgra addon **Ekipa Challenge**,
- zainstaluje mały program **uploader**, który wysyła dane na stronę i włącza się sam razem z Windowsem.

Na końcu zobaczysz zielony napis **„=== Gotowe! ===”**. Możesz zamknąć okno.

### Gdyby skrypt zapytał o folder gry

Jeśli zobaczysz „Nie znalazłem folderu World of Warcraft”:
1. Otwórz aplikację **Battle.net** i wybierz **World of Warcraft**.
2. Kliknij **koło zębate ⚙️** obok niebieskiego przycisku „Graj” → **Pokaż w Eksploratorze**.
3. Otworzy się folder. Kliknij w **pasek adresu** na górze okna (tam, gdzie jest np. `D:\Gry\World of Warcraft`),
   skopiuj tekst (**Ctrl + C**).
4. Wróć do okna PowerShell, wklej (**prawy przycisk myszy**) i naciśnij **Enter**.

Jeśli zapyta o **numer wersji gry** – wpisz numer przy tej, w którą grasz (np. przy `_forever_`) i **Enter**.

## Krok 3. Włącz addon w grze

1. Uruchom WoW. Na ekranie wyboru postaci kliknij **AddOns** (lewy dolny róg).
2. Upewnij się, że **Ekipa Challenge** ma ptaszka ✅.
3. Jeśli na górze jest napis o nieaktualnych addonach (*out of date*), zaznacz **„Wczytuj nieaktualne add-ony”**.
4. Wejdź do gry. Na czacie pojawi się: **„Ekipa v1.0.0 wczytany…”** – działa!

## Krok 4. Graj (i czasem zrób /reload)

**Najważniejsza zasada:** gra zapisuje dane na dysku tylko przy:
- wpisaniu na czacie **`/reload`**,
- wylogowaniu,
- wyjściu z gry.

Dopiero wtedy uploader wysyła je na stronę (w ciągu kilkunastu sekund). Jeśli gra się zawiesi (crash),
przepada wszystko od ostatniego zapisu – dlatego od czasu do czasu wpisz **`/reload`**.
Najlepszy moment: lot taksówką (gryfem / wywerną), statek, zeppelin. Addon sam Ci o tym przypomni na czacie.

### Przydatne komendy w grze

| Komenda | Co robi |
|---|---|
| `/ekipa` | pokazuje, ile danych czeka na zapis i co zebrałeś w tej sesji |
| `/ekipa zapisz` | to samo co `/reload` – zapisuje dane |
| `/ekipa cicho` | wyłącza / włącza przypomnienia o `/reload` |

---

## ❓ Pytania

**Czy muszę coś włączać przed grą?** Nie. Uploader startuje sam z Windowsem i działa w tle bez okna.

**Czy to spowalnia komputer albo grę?** Nie. Uploader co kilkanaście sekund sprawdza jeden plik – to tyle co nic.
Addon tylko notuje zdarzenia z gry.

**Czy to bezpieczne / zgodne z zasadami gry?** Tak. To zwykły addon (jak Details czy Questie) – czyta tylko to,
co gra sama pokazuje addonom. Nie zmienia gry i nie gra za Ciebie. Uploader czyta wyłącznie plik `Ekipa.lua` addonu.

**Komputer był wyłączony / nie było internetu?** Nic nie szkodzi – dane czekają w pliku i pójdą przy następnej okazji.

**Skąd wiem, że działa?** Na stronie w zakładce WoW przy przycisku „🧩 Zainstaluj addon” widać
„✅ Twoje dane: ostatnio … temu”, a na karcie postaci „🧩 addon … temu”.

**Aktualizacje?** Same. Uploader co kilka godzin sprawdza nową wersję i podmienia addon, gdy gra jest wyłączona.

**Zmieniłem komputer / przeinstalowałem Windowsa?** Powtórz kroki 1–3.

**Chcę wszystko usunąć.** Otwórz PowerShell (jak w kroku 2), wklej i naciśnij Enter:
```
irm https://challenge.kubczi.pl/wow/uninstall.ps1 | iex
```

**Coś nie działa.** Wyślij Kubie plik `uploader.log`: naciśnij **Windows + R**, wpisz `%LOCALAPPDATA%\EkipaWoW`
i naciśnij Enter – plik jest w tym folderze.

**Bez uploadera?** Na stronie w panelu addonu („Inne opcje”) jest **Ekipa.zip** (sam addon do ręcznego rozpakowania
w `_forever_\Interface\AddOns`) i przycisk do ręcznego wgrania pliku
`World of Warcraft\_forever_\WTF\Account\<KONTO>\SavedVariables\Ekipa.lua`.
