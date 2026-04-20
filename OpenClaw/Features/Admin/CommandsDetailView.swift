import SwiftUI

struct CommandsDetailView: View {
    @State var commandsVM: CommandsViewModel
    @State private var commandToConfirm: QuickCommand?

    private let columns = QuickCommand.gridColumns

    init(commandsVM: CommandsViewModel) {
        self.commandsVM = commandsVM
    }

    var body: some View {
        List {
            Section("命令") {
                LazyVGrid(columns: columns, spacing: Spacing.xs) {
                    ForEach(QuickCommand.all) { cmd in
                        CommandButton(
                            command: cmd,
                            isRunning: commandsVM.isCommandRunning(cmd.id)
                        ) {
                            commandToConfirm = cmd
                        }
                    }
                }
                .padding(.vertical, Spacing.xxs)
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                DetailTitleView(title: "命令中心") {
                    Text("运行维护命令")
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }
            }
        }
        .alert("运行命令？", isPresented: Binding(
            get: { commandToConfirm != nil },
            set: { if !$0 { commandToConfirm = nil } }
        )) {
            Button("运行", role: .destructive) {
                guard let cmd = commandToConfirm else { return }
                Task { await commandsVM.execute(cmd) }
            }
            Button("取消", role: .cancel) { commandToConfirm = nil }
        } message: {
            if let cmd = commandToConfirm {
                Text(cmd.confirmMessage)
            }
        }
        .sheet(item: $commandsVM.result) { result in
            CommandResultSheet(result: result, vm: commandsVM)
        }
    }
}
