import AppKit
import SwiftUI

@main
struct AllocatorApp: App {
    private let model: AllocatorModel

    init() {
        model = AllocatorModel()
        NSWindow.allowsAutomaticWindowTabbing = false
        // Run from a terminal as a bare executable, so ask for a Dock icon and focus.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
    }

    var body: some Scene {
        Window("Income Allocator", id: "allocator") {
            AllocatorView(model: model)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .pasteboard) {
                Button("Copy Report") {
                    model.copyReport()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
    }
}
