import SwiftUI

@main
struct modsApp: App {
    @FocusedValue(\.openFileAction) private var openFileAction

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
        }
    }
}

struct OpenFileActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var openFileAction: (() -> Void)? {
        get { self[OpenFileActionKey.self] }
        set { self[OpenFileActionKey.self] = newValue }
    }
}
