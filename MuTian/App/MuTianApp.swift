import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct MuTianApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var libraryStore = LibraryStore()
    @StateObject private var settingsStore = SettingsStore()
    @StateObject private var downloadStore = DownloadTaskStore()

    var body: some Scene {
        WindowGroup("木天") {
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

        WindowGroup("全屏阅读", for: UUID.self) { $bookID in
            FullScreenReaderWindow(bookID: bookID)
                .environmentObject(libraryStore)
                .frame(minWidth: 900, minHeight: 680)
        }
        .defaultSize(width: 1280, height: 860)

        Settings {
            SettingsView()
                .environmentObject(settingsStore)
        }
    }
}
