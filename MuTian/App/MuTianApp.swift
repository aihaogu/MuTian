import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var prepareForTermination: (() -> Bool)?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard prepareForTermination?() != false else {
            let alert = NSAlert()
            alert.messageText = "尚有数据未能保存"
            alert.informativeText = "请检查资料库或下载页的错误提示，修复后再退出。"
            alert.runModal()
            return .terminateCancel
        }
        return .terminateNow
    }

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
                .onAppear {
                    appDelegate.prepareForTermination = {
                        let librarySaved = libraryStore.flush()
                        let downloadsSaved = downloadStore.shutdown()
                        return librarySaved && downloadsSaved
                    }
                }
        }
        .commands {
            CommandMenu("资料库") {
                Button("导入文件夹...") {
                    libraryStore.presentImportPanel()
                }
                .keyboardShortcut("i", modifiers: [.command])

                Button("重新扫描全部") {
                    Task {
                        await libraryStore.rescanKnownRoots()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                OpenLibraryFoldersButton()
                    .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }

        Window("资料库文件夹", id: LibraryFoldersWindow.id) {
            LibraryFoldersView()
                .environmentObject(libraryStore)
        }
        .defaultSize(width: 680, height: 460)

        WindowGroup("阅读", for: UUID.self) { $bookID in
            ReaderWindow(bookID: bookID)
                .environmentObject(libraryStore)
        }
        .defaultSize(width: 1100, height: 820)

        Settings {
            SettingsView()
                .environmentObject(settingsStore)
                .environmentObject(libraryStore)
        }
    }
}
