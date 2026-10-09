# Seri AI — Voice Assistant

Seri is a Flutter voice assistant with a futuristic JARVIS-inspired interface, speech recognition, spoken replies, quick commands, and an optional connection to your own AI backend.

## Features
- Speech-to-text microphone input and text chat
- Spoken answers using the device's text-to-speech engine
- Quick actions: time, date, Google search, and opening popular websites
- Optional configurable AI chat endpoint
- Dark sci-fi interface with an animated assistant core

## Run
```bash
flutter pub get
flutter run
```

Build a release APK:
```bash
flutter build apk --release
```

## Connect an AI backend
Deploy an HTTP endpoint that accepts JSON such as `{"message":"Hello"}` and returns JSON with a `reply`, `response`, `answer`, or `message` field. Build with:
```bash
flutter build apk --release --dart-define=SERI_API_URL=https://your-server.example.com/chat
```
You can also enter the endpoint in Seri's settings. Keep provider API keys on the server, never inside the app.

## Android permissions
In `android/app/src/main/AndroidManifest.xml`, declare:
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
```
Speech recognition depends on device speech services. Seri does not continuously listen in the background; tap the microphone to start.
