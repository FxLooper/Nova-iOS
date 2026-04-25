# Nova — průvodce screenshoty pro App Store

Stav: verze 13.4.7 (build 43). Tento guide je finální plán toho, co nafotit.

## Povinné velikosti (2026)

- **6.9" display (iPhone 16 Pro Max, 17 Pro Max)** — 1320 × 2868 px (portrait), POVINNÉ
- **6.5" display (iPhone 11 Pro Max, XS Max)** — 1242 × 2688 px (portrait), povinné pro starší review
- iPad Pro 13" — neřešíme, Nova je iPhone-only

Pokud nahraješ jen 6.9" variantu, App Store ji automaticky downscaluje pro menší zařízení. Pro jistotu přesto pošli i 6.5".

## Pořizování screenshotů

1. V Xcode spusť Nova na simulátoru **iPhone 16 Pro Max** (to je 6.9").
2. Použij `xcrun simctl status_bar booted override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularMode active --cellularBars 4` pro čistý marketingový status bar.
3. V onboardingu klikni „Demo Mode" — naplní UI ukázkovými zprávami bez Nova serveru.
4. `Cmd+S` v simulátoru uloží screenshot na Plochu.
5. Pro 6.5" rozměr spusť na simulátoru **iPhone 11 Pro Max** a opakuj.

Screenshoty pak nahraj v App Store Connect → My Apps → Nova → App Store tab → Screenshots.

## Finální sada — 6 screenshotů (priorita podle pořadí)

### 1. Hero — orb a wake word
- **Co zachytit:** hlavní ContentView se světelným orbem uprostřed, krátká welcome zpráva nad ním, status bar v marketingovém stavu.
- **Stav appky:** idle / ready (orb klidný, modré tóny).
- **Overlay text (top):** „Řekni „Hey Nova" a jedeš"
- **Overlay subtitle:** „Hands-free hlasový AI parťák"

### 2. Aktivní konverzace s VAD barge-in
- **Co zachytit:** orb v listening stavu (oranžová pulzace), bublina od uživatele a začátek odpovědi od Novy.
- **Stav appky:** uprostřed konverzace, vidět chat history.
- **Overlay text:** „Přeruš ji kdykoli — jako v reálné konverzaci"

### 3. Dynamic Island Live Activity
- **Co zachytit:** screenshot z reálného iPhonu 14 Pro+ (simulátor neumí Dynamic Island plně) — vidět ostrov ve stavu „listening" s waveform animací, kolem něj jiná appka (např. Maps nebo Safari).
- **Stav appky:** Nova v backgroundu, Live Activity aktivní.
- **Overlay text:** „Vidíš stav i když děláš něco jiného"

### 4. Voice ID enrollment + anti-spoofing
- **Co zachytit:** Settings → Voice Profile screen, kde je vidět progress enrollmentu a hint o anti-spoofingu.
- **Stav appky:** uprostřed enrollment flow, 50–70 % progress.
- **Overlay text:** „Pozná tvůj hlas. Rozliší ho od nahrávky."

### 5. Naplánované úkoly (Scheduled Tasks)
- **Co zachytit:** ScheduledTasksView se 3–4 ukázkovými úkoly (např. „Připomeň schůzku ve 14:00", „Zavolej v pátek v 9:00 s recapem týdne").
- **Stav appky:** seznam s plánovanými úkoly, přehledné karty.
- **Overlay text:** „Nova ti zavolá nebo připomene"

### 6. Privacy-first — vlastní server
- **Co zachytit:** Settings → Connection screen s Tailscale URL polem a indikátorem připojení.
- **Stav appky:** připojeno k vlastnímu Mac serveru přes Tailscale.
- **Overlay text:** „Tvá data nikdy neopouští tvou síť"

## Doporučená paleta a typografie pro overlay text

- Pozadí overlay: **černá #000** s 0.85 opacity, NEBO bílý card přímo přes screenshot s padding.
- Hlavní nadpis: **SF Pro Display Bold**, 64–72 pt, bílá #FFF.
- Subtitle: SF Pro Text Regular, 32 pt, opacity 0.85.
- Bezpečná zóna: nech alespoň 120 px od horního a dolního okraje — App Store ořezává.

## Tipy k polerování

- Texty v bublinách nech krátké, reálně znějící. Žádný lorem ipsum.
- Nepoužívej reálné e-maily, jména, čísla. Vyber neutrální („Petr", „Jana", e-mail typu user@example.com).
- Před pořízením vyčisti notifikační centrum, aby se ti tam nezobrazovala oznámení z jiných apps.
- Tmavý mód vs. světlý: Nova je primárně dark, takže všechny screenshoty pojmi v dark módu — vypadá to konzistentně a lépe se prodává hlavní orb.

## Preview video (volitelné, ale doporučené)

15–30 s záznam z telefonu / simulátoru, 886 × 1920 nebo 1080 × 1920 (portrait), H.264 MP4. Storyboard:

1. **0–3 s:** uživatel řekne „Hey Nova" → orb reaguje, Dynamic Island se rozsvítí.
2. **3–10 s:** Nova odpoví, uživatel ji uprostřed věty přeruší (ukázka VAD barge-in).
3. **10–18 s:** Schová appku, vidět Dynamic Island s pokračující konverzací.
4. **18–25 s:** Otevře Settings, ukáže Voice Profile a Tailscale connection.
5. **25–30 s:** Closing — orb + nápis „Hey Nova".

Pokud nemáš čas na video, App Store ho nevyžaduje.

## Co po Ondřejovi ručně

Tenhle markdown je plán. Reálné screenshoty musíš nafotit ručně — ideálně tak:

- [ ] Hero (orb idle) — 6.9" + 6.5"
- [ ] Konverzace — 6.9" + 6.5"
- [ ] Dynamic Island — z REÁLNÉHO iPhonu 14 Pro+ (simulátor neumí)
- [ ] Voice Profile — 6.9" + 6.5"
- [ ] Scheduled Tasks — 6.9" + 6.5"
- [ ] Settings / Connection — 6.9" + 6.5"

Total: 11–12 obrázků (5× 2 velikosti + 1 z reálného telefonu pro Dynamic Island).
