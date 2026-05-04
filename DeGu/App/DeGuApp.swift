import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct DeGuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var libraryStore = LibraryStore()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var downloadStore = DownloadTaskStore()

    var body: some Scene {
        WindowGroup("得古") {
            ContentView()
                .environmentObject(libraryStore)
                .environmentObject(settingsStore)
                .environmentObject(downloadStore)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .commands {
            CommandMenu("资料库") {
                Button("导入文件夹...") {
                    libraryStore.presentImportPanel()
                }
                .keyboardShortcut("i", modifiers: [.command])

                Button("刷新索引") {
                    Task {
                        await libraryStore.rescanKnownRoots()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settingsStore)
        }
    }
}
