# Scripture Unlock — project structure

An iOS alarm-clock app that makes you answer a Bible question before the alarm
will dismiss. SwiftUI, 72 Swift files.

| | |
|---|---|
| Platform | iOS 26.1+ (`IPHONEOS_DEPLOYMENT_TARGET = 26.1`) |
| Language | Swift 5, SwiftUI |
| Bundle ID | `com.gorobale.Scripture-Unlock` |
| Team | `98DPKSGQ2P`, automatic signing |
| Dependency | [supabase-swift](https://github.com/supabase-community/supabase-swift) 2.46.0 (the only one) |

The Xcode project uses **file-system-synchronized groups**, so new files under
`Scripture_Unlock/` are picked up automatically — you do not edit
`project.pbxproj` to add a file.

## Layout

```
Scripture_Unlock/
├── Scripture_UnlockApp.swift     App entry point
├── ContentView.swift
├── App/                          RootView, NavigationRouter, AppDelegate,
│                                 AlarmIntents (AlarmKit)
├── Models/                       Alarm, AlarmTone, TriviaQuestion,
│                                 UserProfile, VersePack
├── ViewModels/                   AlarmListViewModel, TriviaViewModel
├── Services/                     see table below
├── Views/
│   ├── Auth/                     EmailOTPAuthView
│   ├── Bible/                    reader, chapter grid, audio bar, note sheet,
│   │                             verse quiz sheet
│   ├── Community/                CommunityView, StudySessionView, Leaderboard
│   ├── Home/                     HomeView, AlarmRowView
│   ├── Onboarding/               5-screen flow
│   ├── Packs/                    PacksView, DailyPracticeCard
│   ├── SetAlarm/                 SetAlarmView
│   ├── Settings/                 SettingsView, ProfileView
│   ├── Stats/                    StatsView, AchievementsView
│   ├── Trivia/                   ringing -> question -> reveal -> dismissed
│   ├── Legal/                    privacy policy, terms
│   ├── Shared/                   AppToastView
│   └── DesignSystem.swift
├── Resources/
│   ├── Secrets.xcconfig          gitignored — see Secrets.xcconfig.example
│   ├── questions.json            offline fallback questions
│   └── Sounds/                   10 alarm tones (.caf + .mp3)
└── Assets.xcassets/
```

## Services

| Service | Talks to |
|---|---|
| `SupabaseService` | auth (Apple `signInWithIdToken`, email OTP), Postgres, Realtime |
| `AlarmService` / `AlarmService+AlarmKit` | local notifications + AlarmKit |
| `EthiopianBibleService` | Railway API — Bible text in am/or/ti/en/niv |
| `QuizService`, `StudyGuideService` | Railway API — quiz + study guides |
| `VerseOfDayService`, `VersOfDayAudioPlayer` | Railway API + Supabase Storage |
| `BibleAudioPlayer` | chapter audio streaming |
| `GeminiService`, `QuestionGeneratorAgent` | Gemini — question generation |
| `CommunityService`, `StudySessionRealtimeService` | study rooms + live sessions |
| `VerseMasteryService`, `AchievementService` | progress, streaks, achievements |
| `BookmarkService`, `VerseNoteService` | bookmarks and verse notes |
| `PushNotificationService` | `send-push` Edge Function |
| `TriviaService`, `KeychainHelper` | question flow, token storage |

## Backends

**Supabase** (`bpqauxqpibaosnbvhito`) — Postgres 17, 19 tables, ~28 RPCs, two
Edge Functions (`send-push`, `accountability-email`), and two Storage buckets
(`profile-avatars`, `verse-audio`). Schema lives in `supabase/migrations/`;
function source in `supabase/functions/`.

**Ethiopian Bible API** — FastAPI on Railway, repo `Henzolena/Ethiopian-Bible-Api`
at `ethiopian-bible-api-production.up.railway.app`. Serves Bible text, quiz,
study guides, and generates verse-of-the-day audio (Mistral writes the
devotional, Gemini TTS speaks it, the MP3 lands in Supabase Storage).

## Capabilities

Apple Sign-In, push notifications (`aps-environment: development`),
time-sensitive notifications, background modes `audio` / `fetch` / `processing`,
and `NSAlarmKitUsageDescription` for AlarmKit.

## Tests

`Scripture_UnlockTests/` and `Scripture_UnlockUITests/` are still the Xcode
template stubs — no real coverage yet.
