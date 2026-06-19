import Foundation

enum L10n {
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        let format = NSLocalizedString(key, comment: "")
        return arguments.isEmpty ? format : String(format: format, arguments: arguments)
    }
}
