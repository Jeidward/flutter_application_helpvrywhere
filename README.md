# flutter_application_helpvrywhere

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## How to run the applications

Its important to install flutter SDK and flutter extension on Visual studio code.
 
 - To add the Dart and Flutter extensions to VS Code, visit the Flutter extension's marketplace page, then click Install. If prompted by your browser, allow it to open VS Code.

 -  And to download Flutter SDK

 - Once you have done that Go to View > Command Palette or press Control + Shift + P. Select the Flutter: Select Device command. From the Select Device prompt, select Chrome.

 - Go to Run > Start Debugging or press F5. You will see new that an instance of Chrome should open and start running the app.

 - For andriod same story, IOS can only be run on MAC

# Understanding the Flutter App Structure

This document is for teammates who are new to Flutter. You don't need to memorize everything — just read this once so you know where things live and why.

---

## The one file that starts everything

**`lib/main.dart`** is the entry point of the entire app. When the app launches, it runs the `main()` function inside this file. Think of it as the `index.html` of a website or the `main()` of a Java program. Everything else is called from here. If the app doesn't start, this is the first place to look.

---

## The `lib/` folder — where all your work lives

This is the only folder you will work in 95% of the time. Everything else is generated or managed automatically.

A well-organized `lib/` folder looks like this:

```
lib/
├── main.dart               ← app entry point
├── screens/                ← one file per page/screen
│   ├── home_screen.dart
│   ├── login_screen.dart
│   └── request_screen.dart
├── widgets/                ← reusable UI components
│   ├── request_card.dart
│   └── custom_button.dart
├── services/               ← Firebase calls, API calls
│   ├── auth_service.dart
│   └── firestore_service.dart
└── models/                 ← data structures
    ├── user_model.dart
    └── request_model.dart
```

### What each folder is for

**`screens/`** — Each file is one full page the user sees. If you're building the volunteer matching page, you create `volunteer_screen.dart` here. This is where most of the visible UI code lives.

**`widgets/`** — Reusable UI pieces that appear on multiple screens. For example, if a "help request card" appears on 3 different screens, you build it once here and import it everywhere. Avoids copy-pasting UI code.

**`services/`** — All Firebase/API logic goes here, separated from the UI. A screen should never directly call Firestore — it calls a service, and the service talks to Firebase. This keeps things clean and easy to debug.

**`models/`** — Plain Dart classes that represent your data. For example, a `HelpRequest` model has fields like `title`, `location`, `status`. These are used everywhere to pass data around in a structured way instead of raw Maps.

---

## The files you should never manually edit

| File/Folder | Why you leave it alone |
|---|---|
| `android/` | Native Android project, auto-managed by Flutter |
| `ios/` | Native iOS project, auto-managed by Flutter |
| `windows/`, `macos/` | Desktop platform code, same reason |
| `.dart_tool/` | Flutter's internal build cache |
| `pubspec.lock` | Auto-generated dependency lock file |

---

## The one config file you will edit

**`pubspec.yaml`** is where you add external packages (libraries). For example, to add Firebase:

```yaml
dependencies:
  flutter:
    sdk: flutter
  firebase_core: ^2.0.0       ← you add lines like this
  cloud_firestore: ^4.0.0
```

After editing this file, always run `flutter pub get` in the terminal to download the new packages.

---

## How a screen file is structured

Every screen follows the same pattern:

```dart
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Home')),  // top bar
      body: Center(                          // main content
        child: Text('Hello!'),
      ),
    );
  }
}
```

- `Scaffold` = the blank page template (gives you appBar, body, floatingButton, etc.)
- `build()` = the function Flutter calls to draw the UI. Whatever you return here is what the user sees.
- `StatelessWidget` = screen with no changing data. Use `StatefulWidget` when the screen needs to react to user input or live data.

---

## How screens connect to each other (navigation)

Flutter uses a stack for navigation. You push a new screen on top, and pop it to go back:

```dart
// Go to a new screen
Navigator.push(context, MaterialPageRoute(builder: (_) => RequestScreen()));

// Go back
Navigator.pop(context);
```

---

## How Firebase fits in

Firebase is never called directly from a screen. The flow is always:

```
Screen  →  Service  →  Firebase
```

Example: the volunteer screen wants the list of open requests.

```dart
// services/firestore_service.dart
Future<List<HelpRequest>> getOpenRequests() async {
  final snapshot = await FirebaseFirestore.instance
      .collection('requests')
      .where('status', isEqualTo: 'pending')
      .get();
  return snapshot.docs.map((doc) => HelpRequest.fromMap(doc.data())).toList();
}

// screens/volunteer_screen.dart
final requests = await FirestoreService().getOpenRequests();
```

This way, if Firebase changes, you only update the service file — not every screen.

---

## Quick mental model

> Flutter is a tree of widgets. Everything on screen is a widget nested inside another widget. `main.dart` is the root of the tree. Screens are big branches. Widgets in `widgets/` are small reusable leaves. Services and models are the data flowing through the tree — they are never visible on screen themselves.

---

## Who owns what (for this project)

| Team member | Main files to work in |
|---|---|
| Donghwan (Auth/Profile) | `screens/login_screen.dart`, `services/auth_service.dart`, `models/user_model.dart` |
| Eliot (Community Request) | `screens/request_screen.dart`, `services/request_service.dart`, `models/request_model.dart` |
| Joshua (Volunteer Matching) | `screens/volunteer_screen.dart`, `services/matching_service.dart` |
| Tadeo (AI Feature) | `screens/ai_guide_screen.dart`, `services/ai_service.dart` |

Each person works in their own files. Integration happens in `main.dart` and the navigation setup — that's done together.