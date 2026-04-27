# Nova — App Privacy dotazník (App Store Connect)

Tento návod přesně kopíruje co v App Store Connect → App Privacy zaškrtnout, aby to odpovídalo tomu, co Nova skutečně dělá. Apple tento dotazník porovnává se skutečným chováním appky — když to nesedí, appku zařízne.

## 1. Shromažďujete od uživatele data?

**ANO.** Nova sbírá hlasové nahrávky pro zpracování STT a pro ECAPA-TDNN voice embeddings. Posílá je na uživatelův vlastní Mac server (BYOS — Bring Your Own Server).

## 2. Jaké datové typy Nova shromažďuje?

Zaškrtni v App Store Connect tyto kategorie:

### Contact Info
- **Name** — ANO. Uživatel zadá své jméno v onboardingu (lokálně v UserDefaults).
  - Linked to user: **No**
  - Used for tracking: **No**
  - Purposes: **App Functionality** (Nova oslovuje uživatele jménem)

### User Content
- **Audio Data** — ANO. Hlasové nahrávky během konverzace + voice ID enrollment vzorky pro ECAPA-TDNN.
  - Linked to user: **No**
  - Used for tracking: **No**
  - Purposes: **App Functionality** (STT, speaker recognition, anti-spoofing)

- **Photos or Videos** — ANO. Pouze pokud uživatel přiloží foto/video do konverzace (do 200 MB).
  - Linked to user: **No**
  - Used for tracking: **No**
  - Purposes: **App Functionality** (vizuální analýza obsahu)

- **Other User Content** — ANO. Texty zpráv v konverzaci.
  - Linked to user: **No**
  - Used for tracking: **No**
  - Purposes: **App Functionality**

### Identifiers
- **User ID** — NE (žádný account identifier, Nova nemá účty).
- **Device ID** — NE (APNS device token se posílá výhradně na uživatelův vlastní server pro push notifikace a naplánované úkoly, ne třetí straně).

### Location
- **Coarse Location** — ANO, pouze pokud uživatel povolí (NSLocationWhenInUseUsageDescription).
  - Linked to user: **No**
  - Used for tracking: **No**
  - Purposes: **App Functionality** (počasí, nearby places)

### Diagnostics
- **Crash Data** — zaškrtni ANO pouze pokud máš TestFlight / Apple crash reporting zapnutý.
- **Performance Data** — NE.

## 3. Odkazy (SUPPORT URL + PRIVACY POLICY URL)

Apple vyžaduje veřejnou URL na privacy policy a support.

Minimální privacy policy musí obsahovat:

- Kdo jsi (Ondřej / fxlooper).
- Co Nova sbírá (hlas, text, volitelně poloha).
- Kam to posílá — **výhradně uživatelův vlastní Mac server**, žádná třetí strana, žádná analytika.
- Jak dlouho se to drží — do vymazání konverzace uživatelem.
- Jak uživatel data smaže — tlačítko „Smazat historii" v Settings.
- Kontakt — e-mail.

Návrh umístění (zdarma):
- **Privacy policy**: GitHub Pages — `https://fxlooper.github.io/nova-privacy`
- **Support URL**: stejné doméně `https://fxlooper.github.io/nova-support` nebo rovnou mailto: e-mail.

## 4. Tracking

**Does this app collect data from this app and other companies' apps and websites for tracking purposes?**

**NE.** Nova nepoužívá IDFA, žádné ad networks, žádné analytics SDK. To uveď výslovně.

## 5. Checklist před submit

- [ ] V App Store Connect → App Privacy vyplněn dotazník dle výše
- [ ] Privacy Policy URL veřejně dostupná
- [ ] Support URL veřejně dostupná
- [ ] V Xcode: `ITSAppUsesNonExemptEncryption = false` (už hotové)
- [ ] Usage description stringy v Info.plist přesně popisují, co Nova dělá (už hotové)
- [ ] App Privacy Report generovaný systémem odpovídá (ověř po prvním TestFlight buildu)

## 6. Permissions v aktuálním Info.plist (stav verze 13.4.7)

Aktuálně Nova v `Nova/Info.plist` deklaruje tyto usage description stringy — všechny musí mít odpovídající záznam v App Privacy:

- `NSMicrophoneUsageDescription` — mikrofon (povinné, vždy on)
- `NSSpeechRecognitionUsageDescription` — on-device + serverové STT
- `NSLocationWhenInUseUsageDescription` — lokace (volitelné, pro počasí a místa)
- `NSCameraUsageDescription` — kamera (volitelné, pro vizuální analýzu)
- `NSPhotoLibraryAddUsageDescription` — uložení vygenerovaných obrázků do Fotek
- `NSLocalNetworkUsageDescription` — připojení k Nova serveru přes Bonjour / Tailscale

Push notifikace se registrují runtime přes UNUserNotificationCenter — nevyžaduje string v Info.plist, ale uživatel potvrzuje runtime alert.
