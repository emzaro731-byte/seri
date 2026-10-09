# Seri AI — Voice Assistant

Seri is a Flutter Android voice assistant with speech recognition, spoken replies, a sci-fi interface, quick actions, and an optional AI conversation backend.

## Android app
The Flutter app includes:
- Voice input and text chat
- Spoken responses with a voice-reply toggle
- Quick actions for time, date, Google/YouTube/WhatsApp/Gmail, web search, weather search, and Maps
- Chat history on screen, copy-message buttons, and clear-chat controls
- Optional AI endpoint setting

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

## Android permissions
The Android manifest needs internet and microphone permissions. The GitHub Actions workflow adds them when generating the Android project.

## Notes
- Voice recognition depends on Android's installed speech services.
- Seri listens only when you tap the microphone; it does not continuously record in the background.
- A Render free service may sleep when idle and take time to wake up.
- Never store API keys in Flutter code, GitHub commits, or the APK.
