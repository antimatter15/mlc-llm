import SwiftUI
import GameController


extension Bundle {
  var icon: UIImage? {
    if let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
       let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
       let files = primary["CFBundleIconFiles"] as? [String],
       let icon = files.last
    {
      return UIImage(named: icon)
    }
    return nil
  }
}

struct ChatView: View {
    @EnvironmentObject private var chatState: ChatState
    @State private var inputMessage: String = ""
    @FocusState private var inputIsFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            messagesView
            if chatState.modelChatState != .failed {
                messageInputView
            }
        }
//        .navigationBarTitle("MLC Chat: \(chatState.displayName)", displayMode: .inline)
//        .navigationBarBackButtonHidden()
//        .toolbar {
//            ToolbarItem(placement: .navigationBarLeading) {
//                Button {
//                    dismiss()
//                } label: {
//                    Image(systemName: "chevron.backward")
//                }
//                .buttonStyle(.borderless)
//                .disabled(!chatState.isInterruptible)
//            }
//            ToolbarItem(placement: .navigationBarTrailing) {
//                Button("Reset") {
//                    chatState.requestResetChat()
//                }
//                .padding()
//                .disabled(!chatState.isResettable)
//            }
//        }
        .task {
            // Focus the input field once the model is prepared
            inputIsFocused = true
        }
    }
}

private extension ChatView {
    
    var welcomeView: some View {
        VStack {
            if let appIcon = Bundle.main.icon {
                Image(uiImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
            }

            Text("Welcome to Chat Sheepy-T")
                .font(.headline)
            
            Text("This app runs an instruction-tuned large language model offline on your device.")
                .padding(.top)
                .multilineTextAlignment(.center)
            
            Text("""
                Chat Sheepy-T is developed by Kevin Kwok and powered by Mistral 7B, fine-tuned by Eric Hartford as Dolphin 2.2.1 by Eric Hartford, and MLC LLM, the hardware accelerated language model compiler based on Apache TVM. Talking to Sheepy-T is computationally intensive and may warm up your hands like a nice pair of wool mittens! No animals were harmed in the making of this language model.
                """)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            
        }
        .padding()
    }

    var messagesView: some View {
        ScrollViewReader { scrollViewProxy in
            ScrollView {
                welcomeView
                LazyVStack {
                    ForEach(chatState.messages, id: \.id) { message in
                        MessageView(role: message.role, message: message.message)
                    }
                    .padding(.bottom)
                }
                .onChange(of: chatState.messages) { _ in
                    withAnimation {
                        if let lastMessage = chatState.messages.last {
                            scrollViewProxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }
    var messageInputView: some View {
        HStack {
            TextField("Type your message...", text: $inputMessage, axis: .vertical)
//                .textFieldStyle(RoundedBorderTextFieldStyle())
                .background(Color(.systemBackground)) // Use the system background color
                .padding(.horizontal, 15) // Increase horizontal padding
                .padding(.vertical, 5)
                .clipShape(RoundedRectangle(cornerRadius: 15)) // Increase corner radius
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(Color(.secondarySystemBackground), lineWidth: 1)
                )
                .focused($inputIsFocused)
//                .submitLabel(.go)
//                .onSubmit {
//                    send()
//                }
            
            if inputMessage.isEmpty && chatState.modelChatState == .generating {
                Button(action: {
                    chatState.requestInterruptChat {
                        
                    }
                }) {
                    Image(systemName: "stop")
                }
                .padding(.horizontal, 6.0)
            } else if inputMessage.lowercased() == "reset" || inputMessage.lowercased() == "clear" {
                Button(action: {
                    let mainFeedback = UIImpactFeedbackGenerator(style: .soft)
                    inputMessage = ""
                    chatState.requestResetChat()
                    mainFeedback.impactOccurred()
                }) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .padding(.horizontal, 6.0)
            } else if inputMessage.lowercased() == "stats"  {
                Button(action: {
                    let mainFeedback = UIImpactFeedbackGenerator(style: .soft)
                    inputMessage = ""
                    mainFeedback.impactOccurred()
                    chatState.requestInfoMessage()
                }) {
                    Image(systemName: "timer")
                }
                .padding(.horizontal, 6.0)
            } else {
                Button(action: send) {
//                    Image(systemName: "paperplane")
                    Image(systemName: "arrow.right")

                }
                .padding(.top, 3.0)
                .padding(.horizontal, 6.0)
                .disabled(inputMessage.isEmpty)
            }
        }
        .padding(.bottom)
        .padding(.horizontal)
        
    }
    func send() {
        inputIsFocused = true
        
        let message = inputMessage
        inputMessage = ""
        
        Task {
            if chatState.modelChatState == .generating {
                chatState.requestInterruptChat {
                    chatState.requestGenerate(prompt: message)
                }
            }else{
                chatState.requestGenerate(prompt: message)
            }
        }
        
    }
}
