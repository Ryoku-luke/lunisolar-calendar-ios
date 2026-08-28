import Foundation
#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#endif

// MARK: - 设置页辅助类型与子视图（从 SettingsView.swift 拆分，降低单文件体积与编译器负担）

enum ImportedFileType {
    case ics
    case json
}

extension ImportConflictPolicy {
    public var title: String {
        switch self {
        case .keepLatest: return "保留最新（推荐）"
        case .keepLocal:  return "保留本地"
        case .overwrite:  return "覆盖本地"
        }
    }

    public var subtitle: String {
        switch self {
        case .keepLatest: return "按 updatedAt 谁更新就用谁"
        case .keepLocal:  return "同 id 的外部数据一律跳过"
        case .overwrite:  return "同 id 一律用导入版本覆盖"
        }
    }
}

#if canImport(SwiftUI)

// MARK: - Toast 模型 & 视图

struct ToastMessage: Identifiable, Equatable {
    enum Kind: Equatable { case success, warning, error }
    var id = UUID()
    var kind: Kind
    var text: String
}

struct ToastBannerView: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(bgAccent, .white.opacity(0.1))
            Text(message.text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.label)
                .lineLimit(3)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // iOS 26 液态玻璃：Toast 使用 glassEffect 替代 Material.thickMaterial
        .liquidGlassCard(
            cornerRadius: 16,
            tint: bgAccent,
            borderColor: bgAccent.opacity(0.7),
            borderWidth: 1.0,
            shadowOpacity: 0.14
        )
    }

    private var iconName: String {
        switch message.kind {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.circle.fill"
        }
    }

    private var bgAccent: Color {
        switch message.kind {
        case .success: return .systemGreen
        case .warning: return .systemOrange
        case .error:   return .systemRed
        }
    }
}

// MARK: - 导入冲突策略选择页

struct ConflictPolicyPicker: View {
    @Environment(EventStore.self) private var store
    @Binding var policy: ImportConflictPolicy

    var body: some View {
        Form {
            Section {
                ForEach(ImportConflictPolicy.allCases, id: \.self) { p in
                    Button {
                        policy = p
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.title).foregroundStyle(Color.primary)
                                Text(p.subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(Color.secondaryLabel)
                            }
                            Spacer()
                            if policy == p {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color(hex: "#C41A1A"))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("冲突处理策略")
            } footer: {
                Text("当导入的事件与本地事件 id 相同时如何处理。若选「保留最新」，会按 updatedAt 时间戳比较。")
            }

            Section {
                info(label: "本地事件总数", value: "\(store.events.count)")
            } header: {
                Text("预览")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("导入冲突策略")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func info(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(Color.secondaryLabel)
        }
    }
}

// MARK: - ShareSheet (UIActivityViewController 包装)

#if canImport(UIKit)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - ImportFileModifier（.fileImporter 包装成独立 ViewModifier，降低 body 内联闭包复杂度）

#if canImport(UniformTypeIdentifiers)
struct ImportFileModifier: ViewModifier {
    @Binding var isPresented: Bool
    let fileType: ImportedFileType
    let onResult: (Result<URL, Error>) -> Void

    func body(content: Content) -> some View {
        content.fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: {
                switch fileType {
                case .ics:  return [UTType(filenameExtension: "ics") ?? .data]
                case .json: return [UTType(filenameExtension: "json") ?? .data]
                }
            }()
        ) { result in
            onResult(result)
        }
    }
}
#else
struct ImportFileModifier: ViewModifier {
    @Binding var isPresented: Bool
    let fileType: ImportedFileType
    let onResult: (Result<URL, Error>) -> Void
    func body(content: Content) -> some View { content }
}
#endif

#endif
