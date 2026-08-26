import Foundation

extension Bundle {
    static var resources: Bundle {
        // SPM context: Bundle.module points to the package's bundled resources
        // Xcode App context: Bundle.module is unavailable, resources live in Bundle.main
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }
}
