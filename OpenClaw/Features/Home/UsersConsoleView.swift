import SwiftUI
import UIKit

/// 用户管理控制台 — 对齐 Web 管理端 `/users`：
///   - 搜索 + all/active/suspended/admins 过滤
///   - 每行 swipe / 长按菜单：Suspend/Activate、Promote/Demote、Create Token、Delete
///   - 点击行 → `AdminUserDetailView`
///   - 新建表单支持 display_name + email + role (member/admin)
struct UsersConsoleView: View {
    let adminVM: AdminViewModel

    @State private var showCreateUser = false
    @State private var newName = ""
    @State private var newEmail = ""
    @State private var newRole = "member"
    @State private var isCreating = false
    @State private var actionError: String?
    @State private var issuedToken: String?
    @State private var pendingAction: UsersAction?
    @State private var search = ""
    @State private var filter: UsersFilter = .all

    init(adminVM: AdminViewModel) {
        self.adminVM = adminVM
    }

    enum UsersFilter: String, CaseIterable {
        case all, active, suspended, admin
        var label: String {
            switch self {
            case .all:        return "全部"
            case .active:     return "激活"
            case .suspended:  return "暂停"
            case .admin:      return "Admin"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                profileHero
                statsStrip
                filtersBar
                usersListSection
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
        .sheet(isPresented: $showCreateUser) { createUserSheet }
        .alert("操作失败", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("好的", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .alert("Token 已生成", isPresented: Binding(
            get: { issuedToken != nil },
            set: { if !$0 { issuedToken = nil } }
        )) {
            Button("复制", role: .none) {
                if let t = issuedToken { UIPasteboard.general.string = t }
                issuedToken = nil
            }
            Button("关闭", role: .cancel) { issuedToken = nil }
        } message: {
            Text(issuedToken ?? "")
        }
        .confirmationDialog(
            pendingAction?.title ?? "",
            isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
            titleVisibility: .visible
        ) {
            if let p = pendingAction {
                Button(p.buttonLabel, role: p.destructive ? .destructive : .none) {
                    Task { await performPending(p) }
                }
                Button("取消", role: .cancel) { pendingAction = nil }
            }
        } message: {
            if let p = pendingAction { Text(p.message) }
        }
    }

    private var subtitle: String {
        "\(adminVM.adminUsers.count) 个远端用户"
    }

    // MARK: - Profile hero

    @ViewBuilder
    private var profileHero: some View {
        let profile = adminVM.profile
        let displayName = profile?.displayName ?? "未登录"
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

    // MARK: - Filter bar

    @ViewBuilder
    private var filtersBar: some View {
        VStack(spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppColors.neutral)
                TextField("搜索姓名或邮箱", text: $search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppColors.neutral)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.md)
                    .fill(Color(.systemBackground))
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(UsersFilter.allCases, id: \.rawValue) { f in
                        Button {
                            filter = f
                            Haptics.shared.success()
                        } label: {
                            Text(f.label)
                                .font(AppTypography.nano)
                                .fontWeight(.semibold)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(filter == f ? AppColors.primaryAction : AppColors.primaryAction.opacity(0.08))
                                )
                                .foregroundStyle(filter == f ? Color.white : AppColors.primaryAction)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var filteredUsers: [AdminUserDTO] {
        var list = adminVM.adminUsers
        switch filter {
        case .all: break
        case .active:    list = list.filter { ($0.status ?? "") == "active" }
        case .suspended: list = list.filter { ($0.status ?? "") == "suspended" }
        case .admin:     list = list.filter { ($0.role ?? "") == "admin" }
        }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter { u in
                (u.displayName ?? "").lowercased().contains(q)
                || (u.email ?? "").lowercased().contains(q)
                || u.id.lowercased().contains(q)
            }
        }
        return list
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
                Text("\(filteredUsers.count) / \(adminVM.adminUsers.count)")
                    .font(AppTypography.micro)
                    .foregroundStyle(AppColors.neutral)
            }

            if filteredUsers.isEmpty {
                Text(adminVM.adminUsers.isEmpty ? "没有权限读取 /api/admin/users，或尚未创建用户。" : "没有匹配的用户。")
                    .font(AppTypography.nano)
                    .foregroundStyle(AppColors.neutral)
                    .padding(.vertical, Spacing.sm)
            } else {
                VStack(spacing: Spacing.xs) {
                    ForEach(filteredUsers) { user in
                        NavigationLink {
                            AdminUserDetailView(userId: user.id, adminVM: adminVM)
                        } label: {
                            userRow(user)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { rowMenu(user) }
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
                        .lineLimit(1)
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
                    if let jobs = user.jobCount, jobs > 0 {
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
            Image(systemName: "chevron.right")
                .font(AppTypography.nano)
                .foregroundStyle(AppColors.neutral)
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .fill(Color(.systemGroupedBackground))
        )
    }

    @ViewBuilder
    private func rowMenu(_ user: AdminUserDTO) -> some View {
        let active = (user.status ?? "") == "active"
        if active {
            Button(role: .destructive) {
                pendingAction = .suspend(userId: user.id, name: user.displayName ?? user.id)
            } label: {
                Label("暂停账号", systemImage: "pause.circle")
            }
        } else {
            Button {
                pendingAction = .activate(userId: user.id, name: user.displayName ?? user.id)
            } label: {
                Label("重新激活", systemImage: "play.circle.fill")
            }
        }

        if (user.role ?? "member") == "admin" {
            Button {
                pendingAction = .setRole(userId: user.id, role: "member", name: user.displayName ?? user.id)
            } label: {
                Label("降为 Member", systemImage: "arrow.down.circle")
            }
        } else {
            Button {
                pendingAction = .setRole(userId: user.id, role: "admin", name: user.displayName ?? user.id)
            } label: {
                Label("提升为 Admin", systemImage: "arrow.up.circle.fill")
            }
        }

        Button {
            pendingAction = .createToken(userId: user.id, name: user.displayName ?? user.id)
        } label: {
            Label("签发 Token", systemImage: "key.fill")
        }

        Divider()

        Button(role: .destructive) {
            pendingAction = .delete(userId: user.id, name: user.displayName ?? user.id)
        } label: {
            Label("删除", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: String?) -> some View {
        let value = (status ?? "unknown").lowercased()
        let tint: Color = {
            switch value {
            case "active":     return AppColors.success
            case "suspended":  return AppColors.warning
            case "banned":     return AppColors.danger
            default:           return AppColors.neutral
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
        default:        return AppColors.info
        }
    }

    // MARK: - Create user sheet

    private var createUserSheet: some View {
        NavigationStack {
            Form {
                Section("用户信息") {
                    TextField("显示名", text: $newName)
                        .textInputAutocapitalization(.words)
                    TextField("邮箱（可选）", text: $newEmail)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                    Picker("角色", selection: $newRole) {
                        Text("Member").tag("member")
                        Text("Admin").tag("admin")
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
                    Text("调用 POST /api/admin/users — 创建成功后可能会返回一枚一次性的访问 token。")
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
            let email = newEmail.trimmingCharacters(in: .whitespaces)
            let tokenResp = try await adminVM.createUser(
                displayName: name,
                email: email.isEmpty ? nil : email,
                role: newRole
            )
            newName = ""
            newEmail = ""
            newRole = "member"
            showCreateUser = false
            if let token = tokenResp?.effectiveToken {
                issuedToken = token
            }
            Haptics.shared.success()
        } catch {
            actionError = error.localizedDescription
            Haptics.shared.error()
        }
    }

    private func performPending(_ action: UsersAction) async {
        pendingAction = nil
        do {
            switch action {
            case .suspend(let id, _):
                try await adminVM.suspendUser(id: id)
            case .activate(let id, _):
                try await adminVM.activateUser(id: id)
            case .setRole(let id, let role, _):
                try await adminVM.setUserRole(id: id, role: role)
            case .createToken(let id, let name):
                if let token = try await adminVM.createToken(userId: id, name: "iOS-\(name)") {
                    issuedToken = token
                }
            case .delete(let id, _):
                try await adminVM.deleteUser(id: id)
            }
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

// MARK: - Action enum

enum UsersAction: Identifiable {
    case suspend(userId: String, name: String)
    case activate(userId: String, name: String)
    case setRole(userId: String, role: String, name: String)
    case createToken(userId: String, name: String)
    case delete(userId: String, name: String)

    var id: String {
        switch self {
        case .suspend(let u, _):      return "suspend-\(u)"
        case .activate(let u, _):     return "activate-\(u)"
        case .setRole(let u, let r, _): return "role-\(u)-\(r)"
        case .createToken(let u, _):  return "token-\(u)"
        case .delete(let u, _):       return "delete-\(u)"
        }
    }

    var title: String {
        switch self {
        case .suspend:     return "暂停账号"
        case .activate:    return "重新激活"
        case .setRole(_, let r, _): return r == "admin" ? "提升为 Admin" : "降为 Member"
        case .createToken: return "签发 Token"
        case .delete:      return "删除用户"
        }
    }

    var message: String {
        switch self {
        case .suspend(_, let n):          return "暂停后 “\(n)” 将无法登录。可以随时重新激活。"
        case .activate(_, let n):         return "重新启用 “\(n)” 的账号访问。"
        case .setRole(_, let r, let n):   return "将 “\(n)” 的角色改为 \(r.capitalized)。"
        case .createToken(_, let n):      return "将为 “\(n)” 签发一枚新的 token，仅在下一屏显示一次。"
        case .delete(_, let n):           return "将永久删除 “\(n)”。此操作不可撤销。"
        }
    }

    var buttonLabel: String {
        switch self {
        case .suspend:     return "暂停"
        case .activate:    return "激活"
        case .setRole:     return "保存"
        case .createToken: return "签发"
        case .delete:      return "删除"
        }
    }

    var destructive: Bool {
        switch self {
        case .suspend, .delete: return true
        default: return false
        }
    }
}
