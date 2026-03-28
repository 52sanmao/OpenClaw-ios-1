import SwiftUI

struct MemoryTab: View {
    @State var vm: MemoryViewModel

    var body: some View {
        NavigationStack {
            List {
                // Search
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(AppColors.neutral)
                        TextField("Search memory\u{2026}", text: $vm.searchQuery)
                            .font(AppTypography.body)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { Task { await vm.search() } }
                        if vm.isSearching {
                            ProgressView().scaleEffect(0.7)
                        }
                    }
                }

                // Search results
                if !vm.searchResults.isEmpty {
                    Section("Search Results") {
                        ForEach(vm.searchResults.indices, id: \.self) { index in
                            let result = vm.searchResults[index]
                            if let path = result.path {
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(path)
                                        .font(AppTypography.captionBold)
                                        .foregroundStyle(AppColors.primaryAction)
                                    if let text = result.text {
                                        Text(text.prefix(150))
                                            .font(AppTypography.micro)
                                            .foregroundStyle(AppColors.neutral)
                                            .lineLimit(3)
                                    }
                                }
                                .padding(.vertical, Spacing.xxs)
                            }
                        }
                    }
                }

                // Bootstrap files
                if !bootstrapFiles.isEmpty {
                    Section("Workspace Files") {
                        ForEach(bootstrapFiles) { file in
                            NavigationLink {
                                MemoryFileView(vm: vm, file: file)
                            } label: {
                                FileRow(file: file)
                            }
                        }
                    }
                }

                // Daily logs
                if !dailyLogs.isEmpty {
                    Section("Daily Logs") {
                        ForEach(dailyLogs) { file in
                            NavigationLink {
                                MemoryFileView(vm: vm, file: file)
                            } label: {
                                FileRow(file: file)
                            }
                        }
                    }
                }

                // Reference files
                if !referenceFiles.isEmpty {
                    Section("Reference") {
                        ForEach(referenceFiles) { file in
                            NavigationLink {
                                MemoryFileView(vm: vm, file: file)
                            } label: {
                                FileRow(file: file)
                            }
                        }
                    }
                }

                // Loading / Error / Empty
                if vm.isLoadingFiles {
                    CardLoadingView(minHeight: 60)
                } else if let err = vm.fileError {
                    CardErrorView(error: err, minHeight: 60)
                } else if vm.files.isEmpty && !vm.isLoadingFiles {
                    ContentUnavailableView(
                        "No Files",
                        systemImage: "doc.text",
                        description: Text("No workspace files found.")
                    )
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Memory")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await vm.loadFiles()
                Haptics.shared.refreshComplete()
            }
        }
        .task { await vm.loadFiles() }
    }

    private var bootstrapFiles: [MemoryFile] { vm.files.filter { $0.kind == .bootstrap } }
    private var dailyLogs: [MemoryFile] { vm.files.filter { $0.kind == .dailyLog } }
    private var referenceFiles: [MemoryFile] { vm.files.filter { $0.kind == .reference } }
}

private struct FileRow: View {
    let file: MemoryFile

    var body: some View {
        Label {
            Text(file.name)
                .font(AppTypography.body)
        } icon: {
            Image(systemName: file.icon)
                .foregroundStyle(AppColors.primaryAction)
        }
    }
}
