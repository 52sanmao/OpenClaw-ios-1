import SwiftUI

struct UsersConsoleView: View {
    let accountStore: AccountStore
    let client: GatewayClientProtocol

    var body: some View {
        SettingsView(accountStore: accountStore, client: client)
    }
}
