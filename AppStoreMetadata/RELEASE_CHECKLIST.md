# Nova — release checklist (z lokálního stavu na App Store)

## Kde jsme teď (build 43, verze 13.4.7)

### Hotové
- [x] ITSAppUsesNonExemptEncryption = false v Info.plist
- [x] Všechny usage description stringy přesně popisují chování
- [x] Dynamic Island / Live Activity s animacemi
- [x] Deep link scheme `nova://` (conversation, open, ask)
- [x] NovaWidgets target embed + bundle ID
- [x] Shortcuts + Siri intents (AskNovaIntent, StartNovaConversationIntent, OpenNovaIntent)
- [x] Wake word služba WakeWordService (SFSpeechRecognizer, on-device)
- [x] Wake fráze: „Hi Nova", „Hey Nova", „Ahoj Nova", „Ok Nova" — plus „Novo" s kontextem
- [x] Guest/demo cesta v onboardingu (NoServerInfoSheet)
- [x] Demo banner v hlavičce chatu
- [x] Demo guard ve startConversation() — místo crashe jasná zpráva
- [x] Wake word pauzuje při startu konverzace a obnoví se po jejím konci
- [x] VAD barge-in (přerušení Novy hlasem během odpovědi)
- [x] Voice ID enrollment + anti-spoofing (rule-based přes spectral flatness)
- [x] Video upload do 200 MB
- [x] Naplánované úkoly (scheduled tasks)
- [x] Audit kódu — 0 force unwrap, 0 fatalError, 1 neškodný TODO
- [x] DEBUG obal pro print volání (dlog v KeychainHelper.swift, 102 míst)
- [x] GPS log fix — souřadnice se už nelogují (GDPR)
- [x] App Store popis CS + EN — aktualizováno na 13.4.7
- [x] Privacy dotazník checklist — aktualizováno (Photos/Videos, voice ID)
- [x] Screenshots guide — finální plán 6 scén

## Co zbývá udělat ručně (mimo Xcode)

### V App Store Connect
1. Vytvořit/aktualizovat app record pro Nova
2. Vyplnit App Privacy dotazník podle `PRIVACY_QUESTIONNAIRE.md`
3. Nahrát screenshoty podle `SCREENSHOTS_GUIDE.md` (6.9" a 6.5")
4. Zadat popis z `description_cs.md` / `description_en.md`
5. Zadat keywords, promo text, support URL, privacy policy URL
6. Vybrat kategorii: **Productivity** (primary), **Utilities** (secondary)
7. Věková kategorie: 4+ (žádný explicit content)

### Privacy policy + support URL
- Obsah pro privacy policy je připravený v `PRIVACY_POLICY.md`
- Publikovat přes GitHub Pages na `https://fxlooper.github.io/nova-privacy`
- Support: buď stejná stránka s FAQ, nebo `mailto:` e-mail

### Screenshoty (ručně)
- iPhone 16 Pro Max (6.9") — povinné
- iPhone 11 Pro Max (6.5") — povinné, simulátor stačí
- iPhone 14 Pro+ (reálné zařízení) — kvůli Dynamic Island scéně
- Status bar cleanup (simulátor):
  ```
  xcrun simctl status_bar booted override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
  ```

### V Xcode / terminálu
- Archivovat a nahrát na TestFlight (build 44+):
  ```
  xcodebuild -project Nova.xcodeproj -scheme Nova -configuration Release \
    -archivePath /tmp/Nova.xcarchive -destination 'generic/platform=iOS' archive -quiet
  xcodebuild -exportArchive -archivePath /tmp/Nova.xcarchive \
    -exportOptionsPlist /tmp/ExportOptions.plist -exportPath /tmp/NovaExport \
    -allowProvisioningUpdates
  ```
- Otestovat TestFlight build na reálném zařízení (wake word + Dynamic Island + voice ID)
- Submitnout review

### Manuální test
- Projet kompletní `TEST_CHECKLIST.md` na reálném zařízení (cold start, enrollment, konverzace, wake word, scheduled tasks, privacy)

### Git
- Aktuálně 12+ lokálních commitů oproti origin na `nova-v11-evolution`
- 16 rozeditovaných souborů z dnešního auditu (DEBUG obal, GPS log fix) — commitnout
- Pushnout větev `nova-v11-evolution` na remote
- Vytvořit PR do main a merge
- Otagovat `v13.4.7-build43` stable verzi

## Známé issues (po-release refactor, ne-blocker)
- `pollForResponse` má 193 řádků — rozsekat na menší funkce
- `sendImage` a `sendVideo` mají duplicitní logiku — extrahovat společný upload helper
- OrbWebView TODO: bundlovat Three.js lokálně pro offline mód

## Následný release plan (po submit)

- ML anti-spoofing (CoreML model místo rule-based) — nutná data
- Continuous voice ID adaptation (učení po úspěšných ověřeních)
- Multi-condition voice enrollment (šepot / normál / hlasitý)
- Voice ID export/import (iCloud backup)
- Wake word trénink na vlastních samplech
- Offline TTS fallback (AVSpeechSynthesizer nebo Piper lokálně)
- Home screen widget „rychlý dotaz"
- Apple Watch push-to-talk companion
- End-to-end latence pod 1s
- Ověření všech 16 lokalizací v UI
