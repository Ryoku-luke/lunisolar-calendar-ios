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
        case .keepLatest: return NSLocalizedString("保留最新（推荐）", comment: "")
        case .keepLocal:  return NSLocalizedString("保留本地", comment: "")
        case .overwrite:  return NSLocalizedString("覆盖本地", comment: "")
        }
    }

    public var subtitle: String {
        switch self {
        case .keepLatest: return NSLocalizedString("按 updatedAt 谁更新就用谁", comment: "")
        case .keepLocal:  return NSLocalizedString("同 id 的外部数据一律跳过", comment: "")
        case .overwrite:  return NSLocalizedString("同 id 一律用导入版本覆盖", comment: "")
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
            ZStack {
                Circle()
                    .fill(bgAccent.opacity(0.18))
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(bgAccent)
            }
            .frame(width: 32, height: 32)
            Text(message.text)
                .font(AppTheme.Font.subheadline.weight(.semibold))
                .foregroundStyle(Color.label)
                .lineLimit(3)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
        .glassCard(radius: AppTheme.Radius.lg,
                   material: .thickMaterial,
                   tint: bgAccent,
                   shadow: AppTheme.Shadow.floating)
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
