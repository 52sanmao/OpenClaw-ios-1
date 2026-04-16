import SwiftUI

/// Definition of a quick command button.
struct QuickCommand: Identifiable, Sendable {
    let id: String
    let name: String
    let icon: String
    let iconColor: Color
    let confirmMessage: String
    /// "stats-exec" for /stats/exec, "gateway" for /tools/invoke gateway tool, "pause-all-crons" for batch disable
    let toolName: String
    /// For stats-exec: ["command": "<allowlist-key>"], for gateway: ["action": "restart"]
    let args: [String: String]

    static let all: [QuickCommand] = [
        // Row 1 — visible by default
        QuickCommand(
            id: "restart-gateway",
            name: "重启",
            icon: "arrow.clockwise.circle.fill",
            iconColor: AppColors.warning,
            confirmMessage: "要重启 IronClaw 服务吗？活动会话会自动重新连接。",
            toolName: "gateway",
            args: ["action": "restart"]
        ),
        QuickCommand(
            id: "doctor",
            name: "体检",
            icon: "stethoscope.circle.fill",
            iconColor: AppColors.metricPositive,
            confirmMessage: "要对 IronClaw 服务和所有组件执行健康检查吗？",
            toolName: "stats-exec",
            args: ["command": "doctor"]
        ),
        QuickCommand(
            id: "tail-logs",
            name: "日志尾部",
            icon: "doc.text.magnifyingglass",
            iconColor: AppColors.info,
            confirmMessage: "要获取最新 50 行 IronClaw 服务日志吗？",
            toolName: "stats-exec",
            args: ["command": "logs"]
        ),
        // Row 2 — visible by default
        QuickCommand(
            id: "gateway-status",
            name: "状态",
            icon: "heart.circle.fill",
            iconColor: AppColors.success,
            confirmMessage: "要检查 IronClaw 服务和渠道状态吗？",
            toolName: "stats-exec",
            args: ["command": "status"]
        ),
        QuickCommand(
            id: "security-audit",
            name: "安全",
            icon: "lock.shield.fill",
            iconColor: AppColors.metricTertiary,
            confirmMessage: "要对 IronClaw 服务执行完整安全审计吗？",
            toolName: "stats-exec",
            args: ["command": "security-audit"]
        ),
        QuickCommand(
            id: "backup",
            name: "备份",
            icon: "externaldrive.fill.badge.checkmark",
            iconColor: AppColors.metricPrimary,
            confirmMessage: "要创建完整 IronClaw 服务备份吗？这可能需要一点时间。",
            toolName: "stats-exec",
            args: ["command": "backup"]
        ),
        // Row 3+ — behind "View Details"
        QuickCommand(
            id: "pause-all-crons",
            name: "暂停定时任务",
            icon: "pause.circle.fill",
            iconColor: AppColors.danger,
            confirmMessage: "要禁用全部定时任务吗？在重新启用前，所有计划任务都不会运行。",
            toolName: "pause-all-crons",
            args: [:]
        ),
        QuickCommand(
            id: "channel-status",
            name: "渠道",
            icon: "bubble.left.and.bubble.right.fill",
            iconColor: AppColors.metricHighlight,
            confirmMessage: "要检查所有消息渠道的状态吗？",
            toolName: "stats-exec",
            args: ["command": "channels-status"]
        ),
        QuickCommand(
            id: "memory-index",
            name: "重建索引",
            icon: "brain.fill",
            iconColor: AppColors.metricWarm,
            confirmMessage: "要强制重建语义记忆存储的索引吗？",
            toolName: "stats-exec",
            args: ["command": "memory-reindex"]
        ),
        QuickCommand(
            id: "session-cleanup",
            name: "清理",
            icon: "trash.circle.fill",
            iconColor: AppColors.neutral,
            confirmMessage: "要执行会话维护吗？旧会话将被清理。",
            toolName: "stats-exec",
            args: ["command": "session-cleanup"]
        ),
        QuickCommand(
            id: "plugin-update",
            name: "更新插件",
            icon: "arrow.down.circle.fill",
            iconColor: AppColors.metricSecondary,
            confirmMessage: "要将所有已安装插件更新到最新版本吗？",
            toolName: "stats-exec",
            args: ["command": "plugin-update"]
        ),
        QuickCommand(
            id: "config-validate",
            name: "校验",
            icon: "checkmark.seal.fill",
            iconColor: AppColors.success,
            confirmMessage: "要校验 IronClaw 服务配置文件吗？",
            toolName: "stats-exec",
            args: ["command": "config-validate"]
        ),
    ]

    static let visibleCount = 6
    static let gridColumns = Array(repeating: GridItem(.flexible(), spacing: Spacing.xs), count: 3)
}
