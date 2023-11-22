//
//  ChatState.swift
//  LLMChat
//

import Foundation
import MLCSwift

enum MessageRole {
    case user
    case bot
}

extension MessageRole {
    var isUser: Bool { self == .user }
}

struct MessageData: Hashable {
    let id = UUID()
    var role: MessageRole
    var message: String
}

final class ChatState: ObservableObject {
    enum ModelChatState {
        case generating
        case resetting
        case reloading
        case terminating
        case ready
        case failed
        case pendingImageUpload
        case processingImage
        case starting
    }

    @Published var messages = [MessageData]()
    @Published var infoText = ""
    @Published var displayName = ""
    @Published var useVision = false
    
    private let modelChatStateLock = NSLock()
    @Published var modelChatState: ModelChatState = .starting

    private let threadWorker = ThreadWorker()
    private let chatModule = ChatModule()
    private var modelLib = ""
    private var modelPath = ""
    var localID = ""
    
    init() {
        threadWorker.qualityOfService = QualityOfService.userInteractive
        threadWorker.start()
        
    }
    
    var isInterruptible: Bool {
        return getModelChatState() == .ready
        || getModelChatState() == .generating
        || getModelChatState() == .failed
        || getModelChatState() == .pendingImageUpload
        || getModelChatState() == .starting
    }

    var isChattable: Bool {
        return getModelChatState() == .ready
    }

    var isUploadable: Bool {
        return getModelChatState() == .pendingImageUpload
    }

    var isResettable: Bool {
        return getModelChatState() == .ready
        || getModelChatState() == .generating
        || getModelChatState() == .starting
        
    }
    
    func requestResetChat() {
        assert(isResettable)
        interruptChat(prologue: {
            switchToResetting()
        }, epilogue: { [weak self] in
            self?.mainResetChat()
        })
    }
    
    
    func requestInterruptChat(callback: @escaping () -> Void) {
        assert(isInterruptible)
        interruptChat(prologue: {
            switchToResetting()
        }, epilogue: { [weak self] in
            self?.mainInterruptChat()
            callback()
        })
    }
    
    
    
    func requestTerminateChat(callback: @escaping () -> Void) {
        assert(isInterruptible)
        interruptChat(prologue: {
            switchToTerminating()
        }, epilogue: { [weak self] in
            self?.mainTerminateChat(callback: callback)
        })
    }
    
    func requestReloadChat(localID: String, modelLib: String, modelPath: String, estimatedVRAMReq: Int, displayName: String) {
        if (isCurrentModel(localID: localID)) {
            return
        }
        assert(isInterruptible)
        interruptChat(prologue: {
            switchToReloading()
        }, epilogue: { [weak self] in
            self?.mainReloadChat(localID: localID,
                                 modelLib: modelLib,
                                 modelPath: modelPath,
                                 estimatedVRAMReq: estimatedVRAMReq,
                                 displayName: displayName)
        })
    }
    
    func requestGenerate(prompt: String) {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        let mainFeedback = UIImpactFeedbackGenerator(style: .soft)
        feedback.prepare()
        mainFeedback.prepare()
        
        assert(isChattable)
        switchToGenerating()
        appendMessage(role: .user, message: prompt)
        appendMessage(role: .bot, message: "")
        
        mainFeedback.impactOccurred()
        
        threadWorker.push {[weak self] in
            guard let self else { return }
//            var lastToken = Date()
            chatModule.prefill(prompt)
            var lastText = ""

            while !chatModule.stopped() {
                chatModule.decode()
                
                if let newText = chatModule.getMessage() {
                    DispatchQueue.main.async {
                        if lastText.isEmpty {
                            feedback.impactOccurred()
                            self.updateMessage(role: .bot, message: newText)
                            lastText = newText
                        }else if newText.hasPrefix(lastText) {
                            let newStringIndex = newText.index(newText.startIndex, offsetBy: lastText.count)
                            let newString = newText.suffix(from: newStringIndex)

                            if newString.rangeOfCharacter(from: .punctuationCharacters) != nil {
                                feedback.impactOccurred()
                            } else if newString.contains(" ") {
                                feedback.impactOccurred(intensity: 0.5)
                            }
                            self.updateMessage(role: .bot, message: newText)
                            lastText = newText
                        }else if(newText.isEmpty){
                            self.requestInterruptChat {
                                
                            }
                        }else{
                            self.updateMessage(role: .bot, message: newText)
                            lastText = newText
                        }
                    }
                }

                if getModelChatState() != .generating {
                    break
                }
            }
            mainFeedback.impactOccurred(intensity: 1.0)
            if getModelChatState() == .generating {
                if let runtimeStats = chatModule.runtimeStatsText(useVision) {
                    DispatchQueue.main.async {
                        self.infoText = runtimeStats
                        self.switchToReady()
                    }
                }
            }
        }
    }
    
    func requestInfoMessage(){
        if self.infoText.isEmpty {
            self.appendMessage(role: .bot, message: "No runtime stats available")
        }else{
            self.appendMessage(role: .bot, message: self.infoText)
        }
        
    }

    func requestProcessImage(image: UIImage) {
        assert(getModelChatState() == .pendingImageUpload)
        switchToProcessingImage()
        threadWorker.push {[weak self] in
            guard let self else { return }
            assert(messages.count > 0)
            DispatchQueue.main.async {
                self.updateMessage(role: .bot, message: "[System] Processing image")
            }
            // step 1. resize image
            let new_image = resizeImage(image: image, width: 112, height: 112)
            // step 2. prefill image by chatModule.prefillImage()
            chatModule.prefillImage(new_image, prevPlaceholder: "<Img>", postPlaceholder: "</Img> ")
            DispatchQueue.main.async {
                self.updateMessage(role: .bot, message: "[System] Ready to chat")
                self.switchToReady()
            }
        }
    }

    func isCurrentModel(localID: String) -> Bool {
        return self.localID == localID
    }
}

private extension ChatState {
    func getModelChatState() -> ModelChatState {
        modelChatStateLock.lock()
        defer { modelChatStateLock.unlock() }
        return modelChatState
    }

    func setModelChatState(_ newModelChatState: ModelChatState) {
        modelChatStateLock.lock()
        modelChatState = newModelChatState
        modelChatStateLock.unlock()
    }

    func appendMessage(role: MessageRole, message: String) {
        messages.append(MessageData(role: role, message: message))
    }

    func updateMessage(role: MessageRole, message: String) {
        messages[messages.count - 1] = MessageData(role: role, message: message)
    }

    func clearHistory() {
        messages.removeAll()
        infoText = ""
    }

    func switchToResetting() {
        setModelChatState(.resetting)
    }

    func switchToGenerating() {
        setModelChatState(.generating)
    }

    func switchToReloading() {
        setModelChatState(.reloading)
    }

    func switchToReady() {
        setModelChatState(.ready)
    }

    func switchToTerminating() {
        setModelChatState(.terminating)
    }

    func switchToFailed() {
        setModelChatState(.failed)
    }

    func switchToPendingImageUpload() {
        setModelChatState(.pendingImageUpload)
    }

    func switchToProcessingImage() {
        setModelChatState(.processingImage)
    }

    func interruptChat(prologue: () -> Void, epilogue: @escaping () -> Void) {
        assert(isInterruptible)
        if getModelChatState() == .ready 
            || getModelChatState() == .failed
            || getModelChatState() == .starting
            || getModelChatState() == .pendingImageUpload {
            prologue()
            epilogue()
        } else if getModelChatState() == .generating {
            prologue()
            threadWorker.push {
                DispatchQueue.main.async {
                    epilogue()
                }
            }
        } else {
            assert(false)
        }
    }

    func mainResetChat() {
        threadWorker.push {[weak self] in
            guard let self else { return }
            chatModule.resetChat()
            if useVision {
                chatModule.resetImageModule()
            }
            DispatchQueue.main.async {
                self.clearHistory()
                if self.useVision {
                    self.appendMessage(role: .bot, message: "[System] Upload an image to chat")
                    self.switchToPendingImageUpload()
                } else {
                    self.switchToReady()
                }
            }
        }
    }

    
    func mainInterruptChat() {
        threadWorker.push {[weak self] in
            guard let self else { return }
            chatModule.resetChat()
            if useVision {
                chatModule.resetImageModule()
            }
            DispatchQueue.main.async {
//                self.clearHistory()
                if self.useVision {
                    self.appendMessage(role: .bot, message: "[System] Upload an image to chat")
                    self.switchToPendingImageUpload()
                } else {
                    self.switchToReady()
                }
            }
        }
    }

    
    func mainTerminateChat(callback: @escaping () -> Void) {
        threadWorker.push {[weak self] in
            guard let self else { return }
            if useVision {
                chatModule.unloadImageModule()
            }
            chatModule.unload()
            DispatchQueue.main.async {
                self.clearHistory()
                self.localID = ""
                self.modelLib = ""
                self.modelPath = ""
                self.displayName = ""
                self.useVision = false
                self.switchToReady()
                callback()
            }
        }
    }

    func mainReloadChat(localID: String, modelLib: String, modelPath: String, estimatedVRAMReq: Int, displayName: String) {
        clearHistory()
        let prevUseVision = useVision
        self.localID = localID
        self.modelLib = modelLib
        self.modelPath = modelPath
        self.displayName = displayName
        self.useVision = displayName.hasPrefix("minigpt")
        threadWorker.push {[weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
//                self.appendMessage(role: .bot, message: "[System] Initalize...")
            }
            if prevUseVision {
                chatModule.unloadImageModule()
            }
            chatModule.unload()
            let vRAM = os_proc_available_memory()
//            let requiredMemory = String (
//                format: "%.1fMB", Double(estimatedVRAMReq) / Double(1 << 20)
//            )
            print("Need ram: \(estimatedVRAMReq), available: \(vRAM)")
            if (vRAM < estimatedVRAMReq) {
                
                let errorMessage = (
                    "🐑 Ewe need more RAM 🐏\n\nUnfortunately Sheepy-T is a hungry hungry sheep-o, and only supports devices with 8GB of RAM such as the iPhone 15 Pro and Pro Max."
                )
                DispatchQueue.main.sync {
                    self.messages.append(MessageData(role: MessageRole.bot, message: errorMessage))
                    self.switchToFailed()
                }
                modelChatState = .failed
                return
            }

            
            let startTime = CFAbsoluteTimeGetCurrent()

            if useVision {
                // load vicuna model
                let dir = (modelPath as NSString).deletingLastPathComponent
                let vicunaModelLib = "vicuna-7b-v1.3-q3f16_0"
                let vicunaModelPath = dir + "/" + vicunaModelLib
                let appConfigJSONData = try? JSONSerialization.data(withJSONObject: ["conv_template": "minigpt"], options: [])
                let appConfigJSON = String(data: appConfigJSONData!, encoding: .utf8)
                chatModule.reload(vicunaModelLib, modelPath: vicunaModelPath, appConfigJson: appConfigJSON)
                // load image model
                chatModule.reloadImageModule(modelLib, modelPath: modelPath)
            } else {
                chatModule.reload(modelLib, modelPath: modelPath, appConfigJson: "")
            }
            
            let elapsedTime = CFAbsoluteTimeGetCurrent() - startTime
            print("Reload operation execution time: \(elapsedTime) seconds.")

            DispatchQueue.main.async {
                if self.useVision {
                    self.updateMessage(role: .bot, message: "[System] Upload an image to chat")
                    self.switchToPendingImageUpload()
                } else {
//                    self.updateMessage(role: .bot, message: "[System] Ready to chat")
                    self.switchToReady()
                }
            }
            
            chatModule.processSystemPrompts()
            
        }
    }
}
