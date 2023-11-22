import SwiftUI

@main
struct MLCChatApp: App {
    @StateObject private var appState = AppState()
    @State private var isModelLoaded = false

    init() {
        UITableView.appearance().separatorStyle = .none
        UITableView.appearance().tableFooterView = UIView()
    }

    var body: some Scene {
        WindowGroup {
            // Use the first model's chatState to initialize ChatView
            ChatView()
                .environmentObject(appState.chatState)
                .onAppear {
                    appState.loadAppConfigAndModels()
                    appState.models.first!.startChat(chatState: appState.chatState)
                }
            
        }
    }
}
