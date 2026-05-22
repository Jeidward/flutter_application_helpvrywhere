# HelpVrywhere — Architecture & Interaction Diagrams

These diagrams describe the **AI-overlay assistance flow** that helps elderly
users navigate any app on their phone.

> Both diagrams are written in [Mermaid](https://mermaid.js.org). They render
> directly in GitHub READMEs and inside any Markdown viewer with Mermaid
> support. To export PNG/SVG for slides, paste into <https://mermaid.live>
> and click **Actions → PNG / SVG**.

---

## 1. System Architecture

How the app is layered — from on-device Flutter widgets down to native
Android system services and out to the cloud APIs that power it.

```mermaid
flowchart TB
    classDef ui       fill:#E8EEF8,stroke:#4A90E2,color:#0F172A,stroke-width:1px
    classDef logic    fill:#F3EFFB,stroke:#7C5CD3,color:#0F172A,stroke-width:1px
    classDef native   fill:#FFF7E1,stroke:#D97706,color:#0F172A,stroke-width:1px
    classDef cloud    fill:#E6F7EE,stroke:#1F9D55,color:#0F172A,stroke-width:1px
    classDef bridge   fill:#FCE7F3,stroke:#BE185D,color:#0F172A,stroke-width:1px

    subgraph device[" 📱 User device "]
        direction TB

        subgraph mainEngine[" Flutter — Main Engine (Activity context) "]
            direction TB
            ui[/"UI screens<br/>Auth · Need Help · Help Others<br/>Nearby Requests · Profile"/]:::ui
            bridge["SpeechBridge<br/><i>orchestrates STT · TTS · AI</i>"]:::logic
            stt["speech_to_text<br/><i>STT engine</i>"]:::logic
            tts["flutter_tts<br/><i>TTS engine</i>"]:::logic
            ai["AiService<br/><i>Gemini Vision client</i>"]:::logic
            authS["AuthService"]:::logic
            reqS["RequestService<br/><i>Firestore CRUD</i>"]:::logic
            locS["LocationService<br/><i>Geolocator</i>"]:::logic
        end

        subgraph overlayEngine[" Flutter — Overlay Engine (Service context) "]
            direction TB
            overlayUI["OverlayUI widget<br/><i>Listening indicator · Instruction pill ·<br/>Analyzing · Result card</i>"]:::ui
        end

        subgraph nativeLayer[" Native Android "]
            direction TB
            mainAct["MainActivity<br/><i>MethodChannel host ·<br/>MediaProjection token</i>"]:::native
            capSvc["ScreenCaptureService<br/><i>foreground service<br/>(MediaProjection requirement)</i>"]:::native
            overlaySvc["flutter_overlay_window<br/><i>SYSTEM_ALERT_WINDOW</i>"]:::native
        end

        ports(("IsolateNameServer<br/>ports")):::bridge
    end

    subgraph cloudSide[" ☁️ External services "]
        direction TB
        firebase["Firebase<br/><i>Auth + Firestore<br/>users · requests</i>"]:::cloud
        gemini["Gemini 2.5 Flash<br/><i>Vision API</i>"]:::cloud
        mapbox["Mapbox<br/><i>tiles · directions</i>"]:::cloud
    end

    %% Main engine internal wiring
    ui --> authS
    ui --> reqS
    ui --> locS
    ui -.->|invokes| bridge
    bridge --> stt
    bridge --> tts
    bridge --> ai

    %% Cross-engine bridge
    bridge <-->|status · words · level<br/>analyzing · ai_step · ai_error| ports
    overlayUI <-->|start · stop · analyze<br/>next_step · close| ports

    %% Native bridges
    bridge -->|MethodChannel<br/>takeScreenshot| mainAct
    mainAct --> capSvc
    overlaySvc -.->|hosts second engine| overlayEngine

    %% Cloud
    authS --> firebase
    reqS --> firebase
    ai -->|JPEG + prompt| gemini
    ui -.->|map tiles| mapbox

    %% Layout hint
    overlayEngine -.- nativeLayer
```

### Why two Flutter engines?

The overlay needs to keep running when the user moves to another app
(WhatsApp, Settings, etc.) — that requires it to live in an Android
*Service*, which has no `Activity` context. But `speech_to_text`, `flutter_tts`,
`firebase_auth`, and most Flutter plugins **require** an Activity.

So we split the app:

| Engine | Lives in | What it can do |
|---|---|---|
| **Main** | the launcher Activity | Auth, Firestore, STT, TTS, Gemini calls, screenshots |
| **Overlay** | a foreground Service | Just renders the floating UI + handles user taps |

The two engines can't share memory, so they communicate via Dart
**`IsolateNameServer`** ports — a thin message bus carrying typed
`Map<String, dynamic>` events in both directions.

---

## 2. Interaction Flow (voice-first guidance loop)

End-to-end sequence from "user taps mic" to "user has been guided to the
right tap target". This reflects the **current** voice-first design — the
spatial bounding-box highlight was removed because vision models aren't
reliable enough at pixel coordinates and a screen-blocking overlay made it
impossible for the user to actually tap the target.

```mermaid
sequenceDiagram
    autonumber
    actor U as User
    participant O as Overlay UI
    participant B as SpeechBridge<br/>(main isolate)
    participant S as speech_to_text
    participant N as Native<br/>MediaProjection
    participant G as Gemini Vision
    participant T as flutter_tts

    Note over U,O: 1. Listening phase
    U->>O: Tap mic button
    O->>B: port: { type: "start" }
    B->>S: listen(onResult, onSoundLevel)
    S-->>B: live transcript + amplitude
    B-->>O: port: words / level events
    Note over O: indicator pulses<br/>with voice volume

    Note over U,S: User speaks goal
    S-->>B: final result + listening:false
    O->>B: port: { type: "analyze", text }

    Note over O,N: 2. Capture phase
    B-->>O: port: { type: "hide" }
    Note over O: overlay invisible<br/>for clean screenshot
    B->>N: MethodChannel takeScreenshot
    N-->>B: JPEG bytes (full screen)
    B-->>O: port: { type: "analyzing" }
    Note over O: spinner card

    Note over B,G: 3. AI analysis
    B->>G: POST screenshot + goal<br/>(Gemini 2.5 Flash, JSON mode)
    G-->>B: { instruction, is_complete,<br/>step_number }

    Note over T,O: 4. Guidance phase
    B->>T: speak(instruction)
    T-->>U: 🔊 spoken instruction
    B-->>O: port: { type: "ai_step", ... }

    alt is_complete = false
        O->>O: auto-minimize to<br/>movable instruction pill
        Note over U,O: User reads pill +<br/>listens to TTS, taps target<br/>in underlying app
        U->>O: Tap "I did it → Next"
        O->>B: port: { type: "next_step" }
        Note over B,G: loop → step 4 (capture phase)<br/>same goal, fresh screenshot
    else is_complete = true
        O->>O: expand to success card
        U->>O: Tap "Close Assistant"
        O->>B: port: { type: "close" }
        B->>S: stop()
        B->>T: stop()
        Note over B: clear goal,<br/>step counter, isAnalyzing flag
    end
```

### Why hide the overlay before the screenshot?

`MediaProjection` captures **whatever is on screen at that moment**.
If the overlay is visible, Gemini sees its own card ("Analyzing
screen…") on top of the user's app — which is useless for guidance.
The bridge sends a `hide` message, waits ~250 ms for the next frame,
captures, then sends `analyzing` to bring the card back.

### Why the user-driven "I did it" loop instead of automatic detection?

We considered watching the screenshot pixels for change to auto-advance
steps. We rejected it because:

1. False positives — keyboard pop-ups, notifications, animations all
   change pixels without the user completing the step.
2. The user might still be reading or moving slowly. Forcing the loop
   forward is worse UX than letting them confirm.

The "I did it" button keeps the user in control while the overlay
stays out of their way (collapsed to a 220-px draggable pill).

---

## Tech stack at a glance

| Layer | Technology |
|---|---|
| UI framework | Flutter 3.11+ (Dart) |
| Auth & data | Firebase Auth · Cloud Firestore |
| Speech in | `speech_to_text` (Android STT) |
| Speech out | `flutter_tts` (system TTS) |
| Vision AI | Google Gemini 2.5 Flash (REST + JSON mode) |
| Maps | Mapbox Maps Flutter SDK |
| Screen capture | Android MediaProjection API |
| System overlay | `flutter_overlay_window` + `SYSTEM_ALERT_WINDOW` |
| Inter-isolate IPC | `dart:ui` `IsolateNameServer` ports |

---

## Exporting for slides / PDF

1. Open <https://mermaid.live>.
2. Paste the diagram source from the code block above.
3. **Actions → PNG** for slides, **SVG** for vector use.
4. Pick the **forest** or **base** theme and a 2–3× scale for crisp
   capstone-deck output.
