//
//  Scripture_UnlockApp.swift
//  Scripture_Unlock
//
//  Created by Henok Robale on 5/27/26.
//

import SwiftUI
import SwiftData

@main
struct Scripture_UnlockApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var alarmService       = AlarmService.shared
    @State private var triviaService      = TriviaService.shared
    @State private var supabaseService    = SupabaseService.shared
    @State private var bookmarkService    = BookmarkService.shared
    @State private var noteService        = VerseNoteService.shared
    @State private var achievementService = AchievementService.shared
    @State private var toastService       = ToastService.shared

    init() {
        AppAppearance.configure()

        // Touch AlarmService early so UNUserNotificationCenter.delegate is
        // registered before the system delivers any pending responses.
        _ = AlarmService.shared

        // Warm AI question cache and register for push notifications.
        Task { await PushNotificationService.shared.requestAndRegister() }
        Task {
            for pack in VersePack.all {
                for difficulty in [Difficulty.gentle, .regular, .scholar] {
                    QuestionGeneratorAgent.shared.prefetchIfNeeded(
                        forPack: pack.id, difficulty: difficulty
                    )
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(for: [Alarm.self, UserProfile.self, StreakEntry.self])
                .environment(alarmService)
                .environment(triviaService)
                .environment(supabaseService)
                .environment(bookmarkService)
                .environment(noteService)
                .environment(achievementService)
                .environment(toastService)
        }
    }
}
