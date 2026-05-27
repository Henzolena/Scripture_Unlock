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

    @State private var alarmService = AlarmService.shared
    @State private var triviaService = TriviaService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(for: [Alarm.self, UserProfile.self, StreakEntry.self])
                .environment(alarmService)
                .environment(triviaService)
        }
    }
}
