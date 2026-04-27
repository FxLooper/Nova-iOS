# Nova — Privacy Policy

**Last updated:** 2026-04-25
**App version:** 13.4.7

## Summary (in plain language)

Nova is a personal voice assistant. The app on your iPhone is a client — all your data is processed on **your own private Nova backend server** which you control. We (the app developer) do not run any cloud service, do not collect telemetry, and do not have access to your conversations, voice recordings, or location.

If you use the **Demo / Guest mode**, no server connection is made and no data leaves your device.

## What data the app handles

### Audio (microphone)
- **Why:** to transcribe what you say and recognize who is speaking (voice ID).
- **Where it goes:** sent over an encrypted connection to **your own Nova backend** for transcription. Voice ID enrollment samples and the resulting profile are stored on your backend.
- **What we do not do:** we do not send audio to any third party, we do not retain audio after transcription unless you explicitly enable history on your backend, we do not train any model with your voice.

### Speech recognition (on-device)
- The wake word ("Hey Nova", "Hi Nova", "Ahoj Nova", "Ok Nova") runs **entirely on your device** using Apple's `SFSpeechRecognizer`. Audio used for wake word detection never leaves the iPhone.

### Photos and videos
- **Why:** when you ask Nova to describe a photo, read text, or analyze a video, the file is uploaded to your backend.
- **Where it goes:** to **your own Nova backend** only.
- **Limit:** videos up to 200 MB.

### Location
- **Why:** so Nova can answer "what's the weather here", "find the nearest pharmacy", etc.
- **When:** only while the app is in use, only when a query needs it.
- **Where it goes:** to **your own Nova backend** as a coarse coordinate. Coordinates are **not written to any local log** in version 13.4.7+.

### Notifications
- Used for scheduled tasks ("remind me at 8pm") and Live Activity / Dynamic Island updates during a conversation. No content is sent through Apple Push servers — Live Activities update locally.

### Camera
- Only when you explicitly tap the camera button to capture a photo for Nova to analyze.

### Local network
- Nova connects to your Nova backend on your local network or via Tailscale VPN. We do not scan the network for any other purpose.

## Data we do NOT collect
- No analytics SDK, no crash reporter, no advertising ID.
- No account on any server we run — there is no "Nova cloud".
- No third-party tracking.

## Where data is stored
- **On your iPhone:** your backend server URL, your voice ID profile reference, conversation history (if enabled), keychain credentials for your backend.
- **On your Nova backend:** whatever your backend configuration retains. You control this.
- **Nowhere else.**

## Children
Nova is rated 4+ but is intended for general audiences. We do not knowingly collect data from children because we do not collect data at all.

## Your choices
- Revoke microphone, camera, location, photos, or notifications at any time in iOS Settings → Nova.
- Use **Demo / Guest mode** to try the app with zero network connections.
- Delete the app to remove all locally stored data; ask your backend admin to delete server-side data.

## Encryption
- All connections to your backend use TLS / HTTPS.
- Backend credentials are stored in iOS Keychain.
- The app uses only standard Apple cryptography and does not implement custom encryption (`ITSAppUsesNonExemptEncryption = false`).

## Changes to this policy
If we change this policy, the "Last updated" date at the top will change. Material changes will be announced in the app's release notes.

## Contact
- **Developer:** Ondřej Hladík (fxlooper)
- **Email:** fxlooper.business@gmail.com
- **Privacy URL:** https://fxlooper.github.io/nova-privacy
