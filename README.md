# Seri AI — Voice Assistant

Seri is a Flutter Android voice assistant with speech recognition, spoken replies, a sci-fi interface, quick actions, and an optional AI conversation backend.

## Android app
The Flutter app includes:
- Voice input and text chat
- Optional always-on wake mode with an Android foreground-service notification and automatic listening restarts
- Call and SMS shortcuts that open the Android dialer/message composer for user confirmation
- Spoken responses with a voice-reply toggle
- Quick actions for time, date, Google/YouTube/WhatsApp/Gmail, web search, weather search, and Maps
- Chat history on screen, copy-message buttons, and clear-chat controls
- Optional AI endpoint setting, saved preferences, and voice controls

## Build Android APK
Open **Actions** in this repository and select **Build Seri Android APK**. When the workflow succeeds, download the `seri-android-release` artifact.

You can also build locally in a Flutter environment:
```bash
flutter pub get
flutter build apk --release
```

## Deploy the AI backend to Render
1. Create or open an account on Render and choose **New + → Blueprint**.
2. Connect this repository; Render reads `render.yaml`.
3. In the service environment settings, add `GROQ_API_KEY` with your own provider API key. Do not commit the key into this repository.
4. Deploy and wait for the `/health` check to pass.
5. Open the deployed service URL plus `/health` to confirm it is online.

The API provides `GET /`, `GET /health`, and `POST /chat`. The chat endpoint accepts JSON such as `{"message":"Hello Seri","history":[]}` and returns `{"reply":"..." }`. The provider key is stored on the server, not in the Android app.

## Connect the app
Open Seri → Settings → AI chat endpoint and enter your deployed URL ending in `/chat`, for example `https://your-service.onrender.com/chat`.

Alternatively, build with:
```bash
flutter build apk --release --dart-define=SERI_API_URL=https://your-service.onrender.com/chat
```

## Always-on wake mode
1. Build and install the latest APK from GitHub Actions.
2. Open Seri, grant microphone permission, then open Settings and enable **Always-on “Hey Seri”**.
3. Keep the persistent **Seri is listening** notification visible. The service is started while the app is visible, as required by modern Android microphone foreground-service rules.
4. On ZTE/Android, open Settings → Apps → Seri → Battery (wording varies) and allow background activity or choose Unrestricted if available. Also allow notifications.
5. Say “Hey Seri” while speech recognition is listening. If Android's speech service or battery manager stops listening, automatic restart may be delayed.

Android does not guarantee indefinite microphone access. Force-stopping the app, denying microphone access, some OEM battery controls, or a speech recognition provider timeout can stop listening. Seri does not record continuously to a file; Android speech recognition processes the microphone input.

## Android permissions
The GitHub Actions workflow adds internet, microphone, notification, and microphone foreground-service permissions and the native Android service to the generated Android project.

## Notes
- Voice recognition depends on Android's installed speech services.
- Always-on wake mode uses Android's foreground-service notification and keeps the speech recognizer restarting while the app process remains alive. Android/OEM battery management, speech-service timeouts, microphone permissions, and force-stop can still interrupt it; exempt Seri from battery optimization for best results. This is not a dedicated low-power hardware hotword engine.
- Call and SMS commands open the dialer or composer; Seri does not place calls or send messages automatically.
- A Render free service may sleep when idle and take time to wake up.
- Never store API keys in Flutter code, GitHub commits, or the APK.
