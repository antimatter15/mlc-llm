//
//  MessageView.swift
//  MLCChat
//

import SwiftUI

extension String {
    func removePattern() -> String {
        let pattern = "\\s*<(\\|(i(m(_(e(n(d(\\|>?)?)?)?)?)?)?)?)?$"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(location: 0, length: self.utf16.count)
            return regex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: "")
        }
        return self
    }
    func removingTrailing() -> String {
        let characterSet = CharacterSet(charactersIn: "\u{FFFD}")
        var newString = self
        while let last = newString.unicodeScalars.last, characterSet.contains(last) {
            newString = String(newString.dropLast())
        }
        return newString
    }
    func removeLeading() -> String {
        guard let index = firstIndex(where: { !CharacterSet(charactersIn: String($0)).isSubset(of: .whitespaces) }) else {
            return self
        }
        return String(self[index...])
    }
}


struct MessageView: View {
    let role: MessageRole;
    let message: String
    
    var body: some View {
        let textColor = role.isUser ? Color.white : Color(UIColor.label)
        let background = role.isUser ? Color.blue : Color(UIColor.secondarySystemBackground)
        
        HStack {
            if role.isUser {
                Spacer()
            }
            if message.isEmpty {
                ProgressView()
            } else {
                Text(
                    message.removePattern().removingTrailing()
                        .removeLeading()
                )
                    .padding(10)
                    .foregroundColor(textColor)
                    .background(background)
                    .cornerRadius(10)
                    .textSelection(.enabled)
            }
            
            if !role.isUser {
                Spacer()
            }
        }
        .padding(.horizontal)
        .listRowSeparator(.hidden)
    }
}

struct ImageView: View {
    let image: UIImage

    var body: some View {
        let background = Color.blue
        HStack {
            Spacer()
            Image(uiImage: image)
                .resizable()
                .frame(width: 150, height: 150)
                .padding(15)
                .background(background)
                .cornerRadius(20)
        }
        .padding()
        .listRowSeparator(.hidden)
    }
}

struct MessageView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            VStack (spacing: 0){
                ScrollView {
                    MessageView(role: MessageRole.user, message: "Message 1")
                    MessageView(role: MessageRole.bot, message: "Message 2")
                    MessageView(role: MessageRole.user, message: "Message 3")
                }
            }
        }
    }
}
