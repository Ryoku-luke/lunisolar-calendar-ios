import SwiftUI

/// 设置页「关于」区块：App 图标 + 版本号 + 帮助/反馈/隐私/协议入口
struct AboutSectionView: View {
    @Binding var docToShow: DocKind?

    var body: some View {
        Section {
            VStack(spacing: 8) {
                Image("AppIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous))
                Text(NSLocalizedString("清和日历", comment: "App名"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.label)
                Text("Version \(appVersionString) (\(buildNumber))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .listRowInsets(EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0))
            .listRowBackground(Color.clear)
        } header: {
            Text(NSLocalizedString("关于", comment: ""))
        } footer: {
            Text("© 2026 Qinghe Studio. All rights reserved.")
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
        }

        Section {
            Button { docToShow = .help } label: {
                Label(NSLocalizedString("帮助与说明", comment: ""), systemImage: "questionmark.circle")
            }
            Button { docToShow = .feedback } label: {
                Label(NSLocalizedString("意见反馈", comment: ""), systemImage: "envelope")
            }
            Button { docToShow = .privacy } label: {
                Label(NSLocalizedString("隐私政策", comment: ""), systemImage: "hand.raised")
            }
            Button { docToShow = .agreement } label: {
                Label(NSLocalizedString("用户协议", comment: ""), systemImage: "doc.plaintext")
            }
        }
    }

    private var appVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}
