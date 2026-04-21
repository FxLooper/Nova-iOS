# Nova — release checklist (z lokálního stavu na App Store)

## Kde jsme teď (build 37, verze 10.4.8)

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
- [x] App Store popis CS + EN
- [x] Privacy dotazník checklist
- [x] Screenshots guide

## Co zbývá udělat ručně (mimo Xcode)

### V App Store Connect
1. Vytvořit app record pro Nova (pokud ještě není)
2. Vyplnit App Privacy dotazník podle `PRIVACY_QUESTIONNAIRE.md`
3. Nahrát screenshoty podle `SCREENSHOTS_GUIDE.md` (6.9" a 6.5")
4. Zadat popis z `description_cs.md` / `description_en.md`
5. Zadat keywords, promo text, support URL, privacy policy URL
6. Vybrat kategorii: **Productivity** (primary), **Utilities** (secondary)
7. Věková kategorie: 4+ (žádný explicit content)

### Privacy policy + support URL (cca 30 minut práce)
- Zaregistruj `https://fxlooper.github.io/nova-privacy` přes GitHub Pages
- Support: buď stejná stránka s FAQ, nebo `mailto:` e-mail

### V Xcode / terminálu
- Archivovat a nahrát na TestFlight:
  ```
  xcodebuild -project Nova.xcodeproj -scheme Nova -configuration Release \
    -archivePath /tmp/Nova.xcarchive -destination 'generic/platform=iOS' archive -quiet
  xcodebuild -exportArchive -archivePath /tmp/Nova.xcarchive \
    -exportOptionsPlist /tmp/ExportOptions.plist -exportPath /tmp/NovaExport \
    -allowProvisioningUpdates
  ```
- Otestovat TestFlight build na reálném zařízení (důležité hlavně wake word + Dynamic Island)
- Submitnout review

### Git
- Zkontrolovat 65+ lokálních commitů oproti origin
- Pushnout větev `nova-v11-evolution` na remote
- Vytvořit PR do main a merge
- Otagovat `v10.4.8-build37` stable verzi

## Následný release plan (po submit)

- Wake word trénink na vlastních samplech pro robustnější detekci
- Offline TTS fallback (AVSpeechSynthesizer nebo Piper lokálně)
- Home screen widget „rychlý dotaz"
- Apple Watch push-to-talk companion
- End-to-end latence pod 1s (od tapu po první slovo odpovědi)
- Ověření všech 16 lokalizací v UI
