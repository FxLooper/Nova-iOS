# Nova — manuální test checklist před TestFlight / App Store submission

> Cíl: projet všechny kritické scénáře na reálném zařízení, ať se po review nic nerozsype.
> Testuj na čerstvě nainstalovaném buildu, ideálně i s odhlášeným/guest profilem.

---

## 0. Předpoklady

- [ ] Build z Xcode Release konfigurace (ne Debug — DEBUG print/dlog se v Release nesmí spouštět)
- [ ] Reálné iOS zařízení (iPhone 12+ doporučeno kvůli Dynamic Island)
- [ ] Druhé zařízení nebo simulátor pro guest/demo cestu
- [ ] Server běží a je dostupný (zkontroluj `/api/health`)
- [ ] AirPods nebo sluchátka (test zvukového výstupu / mikrofonu)
- [ ] Stabilní Wi-Fi i mobilní data (test přepínání sítí)

---

## 1. První spuštění (cold install)

- [ ] Po instalaci se zobrazí welcome screen (NoServerInfoSheet nebo SetupView)
- [ ] Žádost o oprávnění mikrofonu — text je v češtině/angličtině podle systému
- [ ] Žádost o speech recognition — text dává smysl
- [ ] Žádost o push notifikace — projde
- [ ] Žádost o lokaci (pokud appka chce) — projde
- [ ] Žádné crashe, žádný bílý screen
- [ ] Onboarding zvládá BYOS i guest/demo cestu

---

## 2. Setup serveru a tokenu

- [ ] Manuální zadání URL serveru a tokenu — uloží se
- [ ] QR kód scanner naskenuje setup z webu a uloží
- [ ] Validace URL (http/https, port) — chybný formát hlásí jasnou chybu
- [ ] Chybný token → backend vrátí 401 → UI hlásí "neplatný token"
- [ ] Server offline → UI hlásí "server nedostupný" (ne crash)
- [ ] Po úspěšném setupu se app rozsvítí, orb naběhne

---

## 3. Hlavní chat (textový vstup)

- [ ] Napsat "Ahoj Novo" — odpověď přijde streamovaně, slovo po slovu
- [ ] Stage indikátor v bublině ukazuje progress (thinking → searching → answering)
- [ ] Zpráva se uloží do historie a zůstane po restartu appky
- [ ] Reset / clear historie funguje a server session se restartuje
- [ ] Velmi dlouhá zpráva (1000+ znaků) — UI zvládá scroll
- [ ] Markdown / odkazy v odpovědích jsou klikatelné
- [ ] Code bloky se renderují čitelně

---

## 4. Hlasová konverzace (push-to-talk)

- [ ] Tap a držení mikrofon tlačítka — orb pulzuje, indikuje listening
- [ ] Krátká věta ("Jak je dnes počasí v Plzni") → správný transcript → odpověď
- [ ] Dlouhá věta (15s+) → transcript je kompletní, žádné useknutí
- [ ] Šepot vs. normální hlasitost → obojí Whisper poznává
- [ ] Český vs. anglický vstup → jazyk se detekuje správně
- [ ] Background hluk (kavárna, ulice) → detekce funguje
- [ ] Po pustění tlačítka se přepne do thinking → speaking
- [ ] Když Nova mluví, lze ji přerušit dalším tap+hold (barge-in)

---

## 5. Wake word "Hey Nova"

- [ ] V settings zapnuto "wake word"
- [ ] Aplikace v popředí — řeknu "Hey Nova" → orb se rozsvítí, listening
- [ ] Variace: "Hi Nova", "Ahoj Nova", "Ok Nova", "Novo" v kontextu
- [ ] False positive test: TV/podcast 5 minut na pozadí — kolik falešných spuštění?
- [ ] Wake word se pauzuje když Nova mluví (žádná smyčka)
- [ ] Wake word se pauzuje při push-to-talk
- [ ] Po skončení konverzace se wake word obnoví

---

## 6. Dynamic Island & Live Activity

- [ ] Při startu konverzace naběhne Live Activity v Dynamic Island
- [ ] Stav listening → speaking → thinking se animuje korektně
- [ ] Tap na Dynamic Island otevře appku zpět do konverzace (deep link `nova://conversation`)
- [ ] Po skončení konverzace Live Activity zmizí (max do 30s)
- [ ] Lock screen — Live Activity je vidět a neodpadává

---

## 7. Voice ID (biometric verification)

- [ ] Enrollment: nahrát hlas — projde, profil se uloží
- [ ] Po enrollmentu: rozpoznám sám sebe → access granted
- [ ] Cizí hlas (kamarád / TV) → access denied, Nova se ozve "neznám tě"
- [ ] Liveness: přehrávání nahrávky z reproduktoru → spoof detected
- [ ] Reset profilu: uloží se nový enrollment, starý zmizí

---

## 8. Memory (dlouhodobé fakta)

- [ ] "Zapamatuj si že bydlím v Plzni" → uloží se
- [ ] V další zprávě / po restartu appky: "Kde bydlím?" → "V Plzni"
- [ ] "Zapomeň že bydlím v Plzni" → smaže se
- [ ] Memory se synchronizuje se serverem (zkontroluj `/api/memory`)

---

## 9. Scheduled tasks / cron / push

- [ ] Vytvořit úkol "připomeň mi za 2 minuty piju vodu"
- [ ] Push notifikace dorazí v daný čas (zařízení může být uzamčené)
- [ ] Tap na notifikaci otevře ScheduledTasksView s detailem
- [ ] Splnění úkolu na serveru se promítne do appky
- [ ] Smazání úkolu se promítne na server

---

## 10. Siri Shortcuts

- [ ] "Hey Siri, ask Nova počasí v Plzni" — projde přes AskNovaIntent
- [ ] "Hey Siri, open Nova" — otevře appku
- [ ] "Hey Siri, start Nova conversation" — spustí konverzaci
- [ ] V Shortcuts.app jsou všechny tři intenty viditelné

---

## 11. Video / foto upload

- [ ] Vyfotit přes kameru → analýza projde, popis dorazí
- [ ] Vybrat fotku z galerie → projde
- [ ] Nahrát video do 200 MB → analýza projde
- [ ] Video > 200 MB → jasná chybová hláška, žádný crash
- [ ] QR kód v obrázku se rozpozná

---

## 12. Network edge cases

- [ ] Wi-Fi → mobilní data uprostřed požadavku → pokračuje nebo elegantně padne
- [ ] Letadlový režim → "offline" indikátor, žádný crash
- [ ] Pomalá síť (Network Link Conditioner: 3G) → timeout je rozumný (max 30s)
- [ ] Server se uprostřed odpovědi rozpadne → fallback HTTP polling zaskočí

---

## 13. Energy & výkon

- [ ] Aplikace v popředí 10 minut s wake word → baterie neklesne výrazně (pod 5 % za 10 min)
- [ ] CPU / GPU profile — orb (Three.js) nedrží 100 % GPU
- [ ] Memory: konverzace se 100+ zprávami nebobtná nad 300 MB
- [ ] Žádný memory leak při opakovaném start/end konverzace (Instruments: Leaks)

---

## 14. UI / UX

- [ ] Light mode (forced `.preferredColorScheme(.light)`) vypadá dobře na všech screenech
- [ ] Dynamic Type: 100 %, 130 %, 200 % — text se nezalomí mimo plochu
- [ ] VoiceOver: orb, mikrofon, send button mají popisky
- [ ] iPhone SE (4.7") vs. iPhone 16 Pro Max — layouty drží
- [ ] Rotace zařízení (pokud je povolena) — nic se nezasekne
- [ ] Klávesnice se neslepuje s input fieldem

---

## 15. Edge cases & odolnost

- [ ] Restart appky uprostřed streaming odpovědi → neztratí se chat
- [ ] Killnout appku přes app switcher → Live Activity zmizí
- [ ] iOS notifikace přijde uprostřed konverzace → nezruší ji
- [ ] FaceTime hovor uprostřed konverzace → audio session přepne, po hovoru obnoví
- [ ] AirPods odpojení uprostřed mluvení → přepne se na speaker, neztichne

---

## 16. Privacy & data

- [ ] Žádný `print()` v Release buildu (jen `dlog` který je v Release no-op)
- [ ] Žádné citlivé údaje (token, transcript) v Console / Crashlytics
- [ ] Privacy policy URL v App Store funguje a vrací reálný text
- [ ] Smazání accountu / odhlášení vyčistí Keychain
- [ ] Žádný analytics SDK bez consent

---

## 17. App Store submission readiness

- [ ] MARKETING_VERSION v Xcode je vyšší než poslední TestFlight build (kontrola `.nova-data/asc-config.json`)
- [ ] CURRENT_PROJECT_VERSION je vyšší než lastBuildNumber
- [ ] Description CS/EN se shoduje s aktuální verzí (pozor na verzi 10.4.8 v textu — opravit před submit!)
- [ ] Privacy questionnaire vyplněný
- [ ] Screenshots nahrané pro 6.9" a 6.5"
- [ ] Keywords vybrané
- [ ] Promo text napsaný
- [ ] Support URL funguje
- [ ] Privacy policy URL funguje
- [ ] Kategorie: Productivity (primary), Utilities (secondary)
- [ ] Věk: 4+
- [ ] ITSAppUsesNonExemptEncryption = false v Info.plist (✅ hotovo)

---

## 18. Po review (po schválení)

- [ ] Stage rollout (1 % → 10 % → 100 %)
- [ ] Sledovat App Store Connect crashes první 48h
- [ ] Sledovat reviews první týden
- [ ] Připravit hotfix branch pro případný urgent bug

---

## Známé issues, které je dobré ověřit (z auditu 25.4.)

- Project warning: `NovaIntents.swift` je v dvou groupách v Xcode projektu (kosmetické, neovlivní funkci, ale stojí za vyčištění)
- 102 původních `print()` převedeno na `dlog()` (DEBUG-only) — ověřit že Release build skutečně nelogí
- Description v `description_cs.md` / `description_en.md` zmiňuje verzi 10.4.8 — aktualizovat na release verzi
- GPS souřadnice se už neloguje plný dict (NovaService.swift ř. 712) — jen "location attached"
- ContentView.swift (2255 ř.) a NovaService.swift (1956 ř.) projité auditem — bez force unwrapů, fatalError, retain cyclů
- Combine subscribery `whisperStateObserver` / `whisperProgressObserver` jsou držené v properties (NovaService.swift ř. 59-60), žádný leak
- `pollForResponse()` v NovaService.swift má 193 řádků (ř. 841-1034) — kandidát na refactor po release, není blocker
- `sendImage` / `sendVideo` mají duplikovanou error/thinkingStage logiku — také po release
