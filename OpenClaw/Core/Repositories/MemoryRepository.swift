import Foundation
import os

private let logger = Logger(subsystem: "co.uk.appwebdev.openclaw", category: "MemoryRepo")

protocol MemoryRepository: Sendable {
    func listFiles() async throws -> [MemoryFile]
    func listSkills() async throws -> [SkillFile]
    func listSkillFiles(skillId: String) async throws -> [SkillFileEntry]
    func readFile(path: String) async throws -> MemoryFileContent
    func readSkillFile(skillId: String, relativePath: String) async throws -> String
}

final class RemoteMemoryRepository: MemoryRepository {
    private let client: GatewayClientProtocol
    private let sessionKey: String
    private let workspaceRoot: String

    init(client: GatewayClientProtocol, sessionKey: String, workspaceRoot: String) {
        self.client = client
        self.sessionKey = sessionKey
        self.workspaceRoot = workspaceRoot
    }

    func listFiles() async throws -> [MemoryFile] {
        logger.debug("memory-list with workspaceRoot: \(self.workspaceRoot)")
        await MainActor.run {
            AppLogStore.shared.append("开始读取记忆文件列表：memory-list root=\(self.workspaceRoot)")
        }

        do {
            let response = try await exec("memory-list", args: workspaceRoot)
            logger.debug("memory-list stdout: \(response.stdout?.prefix(200) ?? "nil"), exitCode: \(response.exitCode ?? -1)")
            let files = MemoryFile.parse(stdout: response.stdout ?? "")
            await MainActor.run {
                AppLogStore.shared.append("记忆文件列表加载成功 count=\(files.count)")
            }
            return files
        } catch {
            guard shouldFallbackToMemoryAPI(error) else { throw error }
            await MainActor.run {
                AppLogStore.shared.append("memory-list 不可用，回退到 /api/memory/list")
            }
            let entries = try await client.listMemoryFiles()
            let files = entries.filter { !($0.isDir ?? false) }.map(mapHTTPMemoryEntry)
            await MainActor.run {
                AppLogStore.shared.append("记忆文件列表通过 /api/memory/list 加载成功 count=\(files.count)")
            }
            return files
        }
    }

    func listSkills() async throws -> [SkillFile] {
        logger.debug("skills-list with workspaceRoot: \(self.workspaceRoot)")
        await MainActor.run {
            AppLogStore.shared.append("开始读取技能列表：skills-list root=\(self.workspaceRoot)")
        }
        let response = try await exec("skills-list", args: workspaceRoot)
        logger.debug("skills-list stdout: \(response.stdout?.prefix(200) ?? "nil"), exitCode: \(response.exitCode ?? -1)")
        let skills = SkillFile.parse(stdout: response.stdout ?? "")
        await MainActor.run {
            AppLogStore.shared.append("技能列表加载成功 count=\(skills.count)")
        }
        return skills
    }

    func listSkillFiles(skillId: String) async throws -> [SkillFileEntry] {
        await MainActor.run {
            AppLogStore.shared.append("开始读取技能文件列表：skill=\(skillId)")
        }
        let response = try await exec("skill-files", args: skillId)
        let entries = SkillFileEntry.parse(stdout: response.stdout ?? "", skillId: skillId)
        await MainActor.run {
            AppLogStore.shared.append("技能文件列表加载成功 skill=\(skillId) count=\(entries.count)")
        }
        return entries
    }

    func readSkillFile(skillId: String, relativePath: String) async throws -> String {
        await MainActor.run {
            AppLogStore.shared.append("开始读取技能文件：skill=\(skillId) path=\(relativePath)")
        }
        let response = try await exec("skill-read", args: "\(skillId) \(relativePath)")
        guard let stdout = response.stdout, !stdout.isEmpty else {
            await MainActor.run {
                AppLogStore.shared.append("技能文件读取失败：空响应 skill=\(skillId) path=\(relativePath)")
            }
            throw MemoryError.fileNotFound("\(skillId)/\(relativePath)")
        }
        await MainActor.run {
            AppLogStore.shared.append("技能文件读取成功：skill=\(skillId) path=\(relativePath) chars=\(stdout.count)")
        }
        return stdout
    }

    func readFile(path: String) async throws -> MemoryFileContent {
        await MainActor.run {
            AppLogStore.shared.append("开始读取记忆文件：path=\(path)")
        }

        if path.hasPrefix("memory/") || path == "MEMORY.md" {
            do {
                let body = MemoryGetToolRequest(path: path, sessionKey: sessionKey)
                let response: MemoryGetResponseDTO = try await client.invoke(body)
                await MainActor.run {
                    AppLogStore.shared.append("记忆文件通过 memory_get 读取成功 path=\(response.path) chars=\(response.text.count)")
                }
                return MemoryFileContent(path: response.path, text: response.text)
            } catch {
                guard shouldFallbackToMemoryAPI(error) else { throw error }
                await MainActor.run {
                    AppLogStore.shared.append("memory_get 不可用，回退到 /api/memory/read path=\(path)")
                }
                let response = try await client.readMemoryFile(path: path)
                await MainActor.run {
                    AppLogStore.shared.append("记忆文件通过 /api/memory/read 读取成功 path=\(response.path) chars=\(response.content.count)")
                }
                return MemoryFileContent(path: response.path, text: response.content)
            }
        } else {
            do {
                let response = try await exec("file-read", args: path)
                guard let stdout = response.stdout, !stdout.isEmpty else {
                    await MainActor.run {
                        AppLogStore.shared.append("记忆文件读取失败：空响应 path=\(path)")
                    }
                    throw MemoryError.fileNotFound(path)
                }
                if let data = stdout.data(using: .utf8),
                   let json = try? JSONDecoder().decode(FileReadResponse.self, from: data) {
                    await MainActor.run {
                        AppLogStore.shared.append("记忆文件通过 file-read 读取成功 path=\(json.path) chars=\(json.text.count)")
                    }
                    return MemoryFileContent(path: json.path, text: json.text)
                }
                await MainActor.run {
                    AppLogStore.shared.append("记忆文件通过 file-read 读取成功 path=\(path) chars=\(stdout.count) raw=true")
                }
                return MemoryFileContent(path: path, text: stdout)
            } catch {
                guard shouldFallbackToMemoryAPI(error) else { throw error }
                await MainActor.run {
                    AppLogStore.shared.append("file-read 不可用，回退到 /api/memory/read path=\(path)")
                }
                let response = try await client.readMemoryFile(path: path)
                await MainActor.run {
                    AppLogStore.shared.append("记忆文件通过 /api/memory/read 读取成功 path=\(response.path) chars=\(response.content.count)")
                }
                return MemoryFileContent(path: response.path, text: response.content)
            }
        }
    }

    // MARK: - Helpers

    private func exec(_ command: String, args: String? = nil) async throws -> StatsExecResponse {
        let body = StatsExecRequest(command: command, args: args)
        do {
            let response: StatsExecResponse = try await client.statsPost("stats/exec", body: body)
            if let exitCode = response.exitCode, exitCode != 0 {
                logger.error("\(command) failed exitCode=\(exitCode) stderr=\(response.stderr ?? "")")
                await MainActor.run {
                    AppLogStore.shared.append("stats/exec 命令失败 command=\(command) exit=\(exitCode) stderr=\(response.stderr ?? "")")
                }
                throw MemoryError.commandFailed(
                    command: command,
                    exitCode: exitCode,
                    stderr: response.stderr ?? ""
                )
            }
            return response
        } catch {
            await MainActor.run {
                if let gatewayError = error as? GatewayError,
                   case .httpError(404, _) = gatewayError {
                    AppLogStore.shared.append("stats/exec 请求失败 command=\(command) args=\(args ?? "") error=当前部署未启用 stats/exec；记忆/技能页不可用，但聊天主链路可能仍正常")
                } else {
                    AppLogStore.shared.append("stats/exec 请求失败 command=\(command) args=\(args ?? "") error=\(error.localizedDescription)")
                }
            }
            throw error
        }
    }

    private func shouldFallbackToMemoryAPI(_ error: Error) -> Bool {
        if let gatewayError = error as? GatewayError {
            switch gatewayError {
            case .httpError(404, _), .serverError(404, _, _):
                return true
            default:
                return false
            }
        }
        return false
    }

    private func mapHTTPMemoryEntry(_ entry: MemoryHTTPEntryDTO) -> MemoryFile {
        let path = entry.path
        let name = entry.name ?? (path as NSString).lastPathComponent
        let kind: MemoryFile.Kind
        if !path.hasPrefix("memory/") {
            kind = .bootstrap
        } else if name.range(of: #"^\d{4}-\d{2}-\d{2}\.md$"#, options: .regularExpression) != nil {
            kind = .dailyLog
        } else {
            kind = .reference
        }
        return MemoryFile(id: path, name: name, path: path, kind: kind)
    }
}

// MARK: - Private DTOs

private struct FileReadResponse: Decodable {
    let text: String
    let path: String
}
