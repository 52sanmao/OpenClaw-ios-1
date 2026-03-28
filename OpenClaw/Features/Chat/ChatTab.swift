import SwiftUI

struct ChatTab: View {
    let client: GatewayClientProtocol

    var body: some View {
        ChatView(vm: ChatViewModel(client: client))
    }
}
