import CloudKit
import Foundation

/// Renders an error chain (CKError + NSError + underlying errors) as a
/// human-readable multi-line string. The whole point is to NEVER hide
/// useful diagnostic detail — the user should be able to read the full
/// reason from the Sync settings pane without diving into Console.
public enum CloudKitErrorDescribe {
    public static func verbose(_ error: any Error, phase: String? = nil) -> String {
        var lines: [String] = []
        if let phase {
            lines.append("\(phase) failed:")
        }
        appendDescription(of: error, depth: 0, into: &lines)
        return lines.joined(separator: "\n")
    }

    private static func appendDescription(
        of error: any Error,
        depth: Int,
        into lines: inout [String]
    ) {
        let indent = String(repeating: "  ", count: depth)
        let nsError = error as NSError

        if let ckError = error as? CKError {
            lines.append("\(indent)CKError code=\(ckError.errorCode) (\(name(of: ckError.code)))")
        } else {
            lines.append("\(indent)\(nsError.domain) code=\(nsError.code)")
        }

        let desc = nsError.localizedDescription
        if !desc.isEmpty {
            lines.append("\(indent)  desc: \(desc)")
        }
        if let reason = nsError.localizedFailureReason {
            lines.append("\(indent)  reason: \(reason)")
        }
        if let suggestion = nsError.localizedRecoverySuggestion {
            lines.append("\(indent)  suggestion: \(suggestion)")
        }

        if let ckError = error as? CKError {
            if let retry = ckError.retryAfterSeconds {
                lines.append("\(indent)  retry-after: \(retry)s")
            }
            if let serverMsg = ckError.userInfo["ServerErrorDescription"] as? String {
                lines.append("\(indent)  server: \(serverMsg)")
            }
            if let partials = ckError.partialErrorsByItemID, !partials.isEmpty {
                lines.append("\(indent)  partial errors (\(partials.count)):")
                for (key, inner) in partials.prefix(5) {
                    lines.append("\(indent)    [\(key)]:")
                    appendDescription(of: inner, depth: depth + 3, into: &lines)
                }
                if partials.count > 5 {
                    lines.append("\(indent)    … +\(partials.count - 5) more")
                }
            }
        }

        let coveredKeys: Set<String> = [
            NSLocalizedDescriptionKey,
            NSLocalizedFailureReasonErrorKey,
            NSLocalizedRecoverySuggestionErrorKey,
            NSUnderlyingErrorKey,
            "NSMultipleUnderlyingErrorsKey",
            "ServerErrorDescription",
            "CKErrorRetryAfterKey",
            "CKPartialErrors",
            "CKPartialErrorsByItemIDKey"
        ]
        for (key, value) in nsError.userInfo where !coveredKeys.contains(key) {
            if value is Error { continue }
            lines.append("\(indent)  \(key): \(value)")
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            lines.append("\(indent)  underlying:")
            appendDescription(of: underlying, depth: depth + 2, into: &lines)
        }

        if let multi = nsError.userInfo["NSMultipleUnderlyingErrorsKey"] as? [any Error], !multi.isEmpty {
            lines.append("\(indent)  multiple underlying (\(multi.count)):")
            for (idx, inner) in multi.prefix(5).enumerated() {
                lines.append("\(indent)    [\(idx)]:")
                appendDescription(of: inner, depth: depth + 3, into: &lines)
            }
            if multi.count > 5 {
                lines.append("\(indent)    … +\(multi.count - 5) more")
            }
        }
    }

    private static func name(of code: CKError.Code) -> String {
        String(describing: code)
    }
}
