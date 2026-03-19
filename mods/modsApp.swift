import SwiftUI

@main
struct modsApp: App {
    @FocusedValue(\.openFileAction) private var openFileAction
    @FocusedValue(\.findAction) private var findAction
    @FocusedValue(\.printAction) private var printAction

    var body: some Scene {
        WindowGroup {
            StartView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    openFileAction?()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .textEditing) {
                Button("Find...") {
                    findAction?()
                }
                .keyboardShortcut("f", modifiers: .command)
            }
            CommandGroup(replacing: .printItem) {
                Button("Print...") {
                    printAction?()
                }
                .keyboardShortcut("p", modifiers: .command)
            }
        }
    }
}

struct OpenFileActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct FindActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct PrintActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var openFileAction: (() -> Void)? {
        get { self[OpenFileActionKey.self] }
        set { self[OpenFileActionKey.self] = newValue }
    }
    var findAction: (() -> Void)? {
        get { self[FindActionKey.self] }
        set { self[FindActionKey.self] = newValue }
    }
    var printAction: (() -> Void)? {
        get { self[PrintActionKey.self] }
        set { self[PrintActionKey.self] = newValue }
    }
}
