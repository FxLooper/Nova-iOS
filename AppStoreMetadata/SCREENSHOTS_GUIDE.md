# Nova — průvodce screenshoty pro App Store

Apple vyžaduje screenshoty pro tyto velikosti (stav 2026):

- **6.9" display (iPhone 16 Pro Max, 17 Pro Max)** — 1320 × 2868 px (portrait), povinné
- **6.5" display (iPhone 11 Pro Max, XS Max)** — 1242 × 2688 px (portrait), povinné pro starší review
- iPad Pro 13" (6. gen) — 2064 × 2752 px — pouze pokud appka běží na iPadu (Nova je iPhone-only)

Pokud nahraješ jen 6.9" variantu, App Store ji automaticky downscaluje pro menší zařízení.

## Pořizování screenshotů

Nejrychlejší cesta:

1. V Xcode spusť Nova na simulátoru **iPhone 16 Pro Max** (to je 6.9").
2. Dev buildy obsahují tlačítko „Demo Mode" v onboardingu — použij ho, aby se UI naplnilo ukázkovými zprávami bez Mac serveru.
3. `Cmd+S` v simulátoru uloží screenshot na Plochu.
4. Pro 6.5" rozměr spusť na simulátoru **iPhone 11 Pro Max** a opakuj.

Screenshoty pak nahraj v App Store Connect → My Apps → Nova → App Store tab → Screenshots.

## Doporučená sada (5 screenshotů)

Apple pustí až 10, ale 5 silných je lepší než 10 rozředěných. Pořadí = priorita viditelnosti.

1. **Hlavní chat s orbem** — uprostřed svítí orb, nad ním název „Nova", pod ním pár ukázkových zpráv. Titulek v headeru: *„Tvoje osobní AI asistentka"*.

2. **Dynamic Island Live Activity** — fotka telefonu, kde je vidět pulzující waveform v ostrovu během konverzace. Titulek: *„Vidíš Novu i když pracuješ dál"*.

3. **Voice Conversation view (orb animace)** — velký centrální orb ve stavu „listening" (oranžová pulzace). Titulek: *„Hlasová konverzace v reálném čase"*.

4. **Siri / Shortcuts integrace** — screenshot systémového Shortcuts UI, kde je vidět „Hi Nova" / „Zeptat se Novy" / „Otevřít Novu". Titulek: *„Řekni „Hi Nova" a jedeš"*.

5. **Privacy-first onboarding** — welcome nebo connection krok s textem o tom, že vše běží lokálně přes Tailscale na vlastní Mac server. Titulek: *„Tvá data nikdy neopouští tvou síť"*.

## Tipy k polerování

- Skryj status bar přes `simctl status_bar override` — nebo použij „Fake Status Bar" v iOS Settings pro Simulátor.
- Typický marketingový status: 9:41, Wi-Fi full, battery 100%.
- Texty v bublinách nech krátké, reálně znějící. Ne lorem ipsum.
- Nepoužívej reálné e-maily / jména.

## Preview video (volitelné, ale doporučené)

15–30 s záznam z telefonu / simulátoru, 886 × 1920 nebo 1080 × 1920 (portrait), H.264 MP4. Ukaž:

- Uživatel řekne „Hi Nova" → orb reaguje → Nova odpoví.
- Dynamic Island přepne do Live Activity.
- Rychlé gesto do Settings → pocit kvalitního UI.

Pokud nemáš čas na video, App Store ho nevyžaduje.
