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

    @State private var alarmService   = AlarmService.shared
    @State private var triviaService  = TriviaService.shared
    @State private var supabaseService = SupabaseService.shared

    init() {
        AppAppearance.configure()

        // Touch AlarmService early so UNUserNotificationCenter.delegate is
        // registered before the system delivers any pending responses.
        _ = AlarmService.shared

        // Warm the AI question cache in the background so questions are ready
        // by the time the first alarm fires.
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
        }
    }
}
