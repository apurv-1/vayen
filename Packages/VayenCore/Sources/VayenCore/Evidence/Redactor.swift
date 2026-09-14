import Foundation

/// Defense-in-depth redaction of recognizable secret patterns before any
/// transcript text leaves the machine. This is NOT a guarantee that arbitrary
/// code contains no secrets; it strips the common credential shapes.
public enum Redactor {

    private static let patterns: [(NSRegularExpression, String)] = {
        let specs: [(String, String)] = [
            // PEM / private key blocks
            (#"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#, "[redacted key block]"),
            // OpenAI / Anthropic / GitHub / Google / Slack style tokens
            (#"sk-(?:ant-)?[A-Za-z0-9_\-]{16,}"#, "[redacted key]"),
            (#"sk-proj-[A-Za-z0-9_\-]{16,}"#, "[redacted key]"),
            (#"(?:ghp|gho|ghu|ghs|ghr|github_pat)_[A-Za-z0-9_]{16,}"#, "[redacted token]"),
            (#"AKIA[0-9A-Z]{16}"#, "[redacted aws key]"),
            (#"xox[baprs]-[A-Za-z0-9\-]{10,}"#, "[redacted token]"),
            (#"AIza[0-9A-Za-z_\-]{35}"#, "[redacted key]"),
            // Bearer tokens and JWTs
            (#"Bearer\s+[A-Za-z0-9_\-\.]{20,}"#, "Bearer [redacted]"),
            (#"eyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}"#, "[redacted jwt]"),
            // Generic assignments: api_key=..., token: ..., password=..., secret=...
            (#"(?i)(api[_-]?key|api[_-]?secret|access[_-]?token|auth[_-]?token|password|passwd|secret|private[_-]?key|client[_-]?secret)\s*[:=]\s*['\"]?[A-Za-z0-9_\-\./\+]{8,}['\"]?"#, "$1=[redacted]"),
        ]
        return specs.compactMap { pattern, template in
            guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (re, template)
        }
    }()

    public static func redact(_ text: String) -> String {
        var result = text
        for (re, template) in patterns {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = re.stringByReplacingMatches(in: result, range: range, withTemplate: template)
        }
        return result
    }
}
