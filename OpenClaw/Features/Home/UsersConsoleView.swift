import SwiftUI

/// 用户管理控制台 — 对接 Web 的「用户管理」：
///   - /api/admin/users：管理员用户列表（含成本与活跃时间）
///   - POST /api/admin/users：新建用户
///   - /api/profile：当前登录人资料
/// 设备侧网关账号切换独立在「设置 · 连接与诊断」页处理，不再与此页混合。
struct UsersConsoleView: View {
    @Bindable var accountStore: AccountStore
    let client: GatewayClientProtocol
    let adminVM: AdminViewModel

    @State private var showCreateUser = false
    @State private var newName: String = ""
    @State private var newRole: String = "member"
    @State private var isCreating = false
    @State private var actionError: String?

    init(accountStore: AccountStore, client: GatewayClientProtocol, adminVM: AdminViewModel) {
        self.accountStore = accountStore
        self.client = client
        self.adminVM = adminVM
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                profileHero
                statsStrip
                usersListSection
                gatewayAccountsCard
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                DetailTitleView(title: "用户管理") {
                    Text(subtitle)
                        .font(AppTypography.micro)
                        .foregroundStyle(AppColors.neutral)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateUser = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .accessibilityLabel("新建用户")
            }
        }
        .refreshable {
            await adminVM.load()
            Haptics.shared.refreshComplete()
        }
        .task {
            if adminVM.adminUsers.isEmpty && !adminVM.isLoading { await adminVM.load() }
        }
        .sheet(isPresented: $showCreateUser) {
            createUserSheet
        }
        .alert("操作失败", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("好的", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private var subtitle: String {
        let cn = adminVM.adminUsers.count
        let local = accountStore.accounts.count
        return "\(cn) 个网关用户 · \(local) 个本地账号"
    }

    // MARK: - Profile hero

    @ViewBuilder
    private var profileHero: some View {
        let profile = adminVM.profile
        let displayName = profile?.displayName ?? accountStore.activeAccount?.name ?? "未登录"
        let email = profile?.email
        let role = profile?.role?.capitalized ?? "Member"

        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Text("当前登录")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.primaryAction)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(AppColors.primaryAction.opacity(0.12)))
                Spacer()
                Label(role, systemImage: "checkmark.shield.fill")
                    .font(AppTypography.nano)
                    .foregroundStyle(AppColors.success)
            }

            HStack(alignment: .center, spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(AppColors.primaryAction.opacity(0.14))
                        .frame(width: 64, height: 64)
                    Text(initials(for: displayName))
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(AppColors.primaryAction)
                }
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(displayName)
                        .font(AppTypography.cardTitle)
                        .lineLimit(1)
                    if let email, !email.isEmpty {
                        Text(email)
                            .font(AppTypography.captionMono)
                            .foregroundStyle(AppColors.neutral)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else if let id = profile?.id {
                        Text(id)
                            .font(AppTypography.captionMono)
                            .foregroundStyle(AppColors.neutral)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .strokeBorder(AppColors.primaryAction.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Stats strip

    @ViewBuilder
    private var statsStrip: some View {
        HStack(spacing: Spacing.sm) {
            statTile(icon: "person.2.fill", value: "\(adminVM.adminUsers.count)", label: "用户", tint: AppColors.metricPrimary)
            statTile(icon: "briefcase.fill", value: "\(totalJobs)", label: "任务数", tint: AppColors.metricTertiary)
            statTile(icon: "dollarsign.circle.fill", value: formattedCost, label: "累计", tint: AppColors.metricWarm)
        }
    }

    private var totalJobs: Int {
        adminVM.adminUsers.reduce(0) { $0 + ($1.jobCount ?? 0) }
    }

    private var formattedCost: String {
        let total = adminVM.adminUsers.reduce(0.0) { acc, u in acc + (Double(u.totalCost ?? "0") ?? 0) }
        return String(format: "$%.2f", total)
    }

    @ViewBuilder
    private func statTile(icon: String, value: String, label: String, tint: Color) -> some View {
        HStack(spacing: Spacing.xs) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(tint.opacity(0.14))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(tint)
                Text(label)
                    .font(AppTypography.nano)
                    .foregroundStyle(AppColors.neutral)
            }
            Spacer()
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }

    // MARK: - Users list

    @ViewBuilder
    private var usersListSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "rectangle.stack.person.crop.fill")
                    .foregroundStyle(AppColors.info)
                Text("网关用户")
                    .font(AppTypography.captionBold)
                Spacer()
                Text("\(adminVM.adminUsers.count) 人")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            }

            if adminVM.adminUsers.isEmpty {
                Text("没有权限读取 /api/admin/users，或尚未创建用户。")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(adminVM.adminUsers) { user in
                        userRow(user)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }

    @ViewBuilder
    private func userRow(_ user: AdminUserDTO) -> some View {
        let roleTint = tint(forRole: user.role)
        HStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(roleTint.opacity(0.14))
                    .frame(width: 40, height: 40)
                Text(initials(for: user.displayName ?? user.id))
                    .font(AppTypography.captionBold)
                    .foregroundStyle(roleTint)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Spacing.xxs) {
                    Text(user.displayName ?? user.id)
                        .font(AppTypography.body)
                        .fontWeight(.medium)
                    Text((user.role ?? "member").capitalized)
                        .font(AppTypography.nano)
                        .padding(.horizontal, Spacing.xxs)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(roleTint.opacity(0.15)))
                        .foregroundStyle(roleTint)
                }
                if let email = user.email, !email.isEmpty {
                    Text(email)
                        .font(AppTypography.nano)
                        .foregroundStyle(AppColors.neutral)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(user.id)
                        .font(AppTypography.nano)
                        .foregroundStyle(AppColors.neutral)
                }
                HStack(spacing: Spacing.xs) {
                    if let jobs = user.jobCount {
                        Label("\(jobs)", systemImage: "briefcase")
                            .font(AppTypography.nano)
                            .foregroundStyle(AppColors.neutral)
                    }
                    if let cost = user.totalCost, let v = Double(cost), v > 0 {
                        Label(String(format: "$%.2f", v), systemImage: "dollarsign.circle")
                            .font(AppTypography.nano)
                            .foregroundStyle(AppColors.neutral)
                    }
                }
            }
            Spacer()
            statusBadge(user.status)
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(Color(.systemGroupedBackground))
        )
    }

    @ViewBuilder
    private func statusBadge(_ status: String?) -> some View {
        let value = (status ?? "unknown").lowercased()
        let tint: Color = {
            switch value {
            case "active": return AppColors.success
            case "suspended", "inactive": return AppColors.warning
            case "banned", "revoked": return AppColors.danger
            default: return AppColors.neutral
            }
        }()
        Text(value.capitalized)
            .font(AppTypography.nano)
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.15)))
            .foregroundStyle(tint)
    }

    private func tint(forRole role: String?) -> Color {
        switch (role ?? "").lowercased() {
        case "admin":   return AppColors.danger
        case "member":  return AppColors.metricPrimary
        case "viewer":  return AppColors.neutral
        default:        return AppColors.info
        }
    }

    // MARK: - Gateway accounts (local)

    @ViewBuilder
    private var gatewayAccountsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "iphone.gen3")
                    .foregroundStyle(AppColors.metricHighlight)
                Text("本地网关账号")
                    .font(AppTypography.captionBold)
                Spacer()
                Text("\(accountStore.accounts.count) 个")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            }

            if let active = accountStore.activeAccount {
                HStack(spacing: Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(AppColors.success.opacity(0.14))
                            .frame(width: 34, height: 34)
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppColors.success)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(active.name)
                            .font(AppTypography.body)
                            .fontWeight(.medium)
                        Text(active.displayURL)
                            .font(AppTypography.nano)
                            .foregroundStyle(AppColors.neutral)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text("使用中")
                        .font(AppTypography.nano)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(AppColors.success.opacity(0.15)))
                        .foregroundStyle(AppColors.success)
                }
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.md)
                        .fill(Color(.systemGroupedBackground))
                )
            }

            Text("新增或切换本地连接请到「设置 · 连接与诊断」。")
                .font(AppTypography.nano)
                .foregroundStyle(AppColors.neutral)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(Color(.systemBackground))
        )
    }

    // MARK: - Create user sheet

    private var createUserSheet: some View {
        NavigationStack {
            Form {
                Section("用户信息") {
                    TextField("显示名", text: $newName)
                        .textInputAutocapitalization(.words)
                    Picker("角色", selection: $newRole) {
                        Text("Member").tag("member")
                        Text("Admin").tag("admin")
                        Text("Viewer").tag("viewer")
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Button {
                        Task { await createUser() }
                    } label: {
                        HStack {
                            if isCreating { ProgressView().scaleEffect(0.75) }
                            Text(isCreating ? "创建中…" : "创建用户")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                } footer: {
                    Text("调用 POST /api/admin/users — 需要 admin 权限。")
                }
            }
            .navigationTitle("新建用户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { showCreateUser = false }
                }
            }
        }
    }

    // MARK: - Actions

    private func createUser() async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            try await adminVM.createUser(displayName: name, role: newRole)
            newName = ""
            newRole = "member"
            showCreateUser = false
            Haptics.shared.success()
        } catch {
            actionError = error.localizedDescription
            Haptics.shared.error()
        }
    }

    private func initials(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "?" }
        if trimmed.unicodeScalars.first?.value ?? 0 >= 0x4E00 {
            return String(trimmed.prefix(1))
        }
        let parts = trimmed.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map { String($0) }.joined().uppercased()
    }
}
