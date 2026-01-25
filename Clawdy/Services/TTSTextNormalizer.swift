import Foundation

/// Normalizes technical content for natural text-to-speech rendering.
/// Handles file paths, URLs, inline code, and other technical content that
/// would sound awkward if read character-by-character by TTS.
///
/// This struct provides static methods to transform technical content into
/// human-friendly spoken forms before the text is sent to the TTS engine.
///
/// ## Examples
/// - `/path/to/IncrementalTTSManager.swift` → "file IncrementalTTSManager.swift"
/// - `https://github.com/user/repo` → "link to github.com"
/// - `$OPENAI_API_KEY` → "variable OPENAI API KEY"
struct TTSTextNormalizer {
    
    // MARK: - Public API
    
    /// Normalize text for natural TTS rendering.
    /// Transforms technical content (file paths, URLs, code references) into
    /// human-friendly spoken forms.
    /// - Parameter text: Raw text that may contain technical content
    /// - Returns: Text with technical content normalized for speech
    static func normalize(_ text: String) -> String {
        var result = text
        
        // Order matters:
        // 1. URLs first - must process before file paths since file path regex could match URL paths
        // 2. Inline code - removes backticks and normalizes content
        // 3. File paths - after URLs are handled, remaining paths are actual file paths
        // 4. Environment variables last
        result = normalizeURLs(result)
        result = normalizeInlineCode(result)
        result = normalizeFilePaths(result)
        result = normalizeEnvironmentVariables(result)
        
        return result
    }
    
    // MARK: - File Path Normalization
    
    /// Normalizes file paths to spoken form.
    /// Extracts the basename and announces it as "file [name]".
    /// Handles Unix paths (/path/to/file), relative paths (./file), and Windows paths (C:\path).
    /// - Parameter text: Text that may contain file paths
    /// - Returns: Text with file paths normalized
    static func normalizeFilePaths(_ text: String) -> String {
        var result = text
        
        // Pattern matches:
        // - Unix absolute paths: /path/to/file.ext
        // - Relative paths: ./path/to/file or ../path/to/file
        // - Paths with common extensions (helps disambiguate from plain slashes)
        // - Paths starting with ~/ (home directory)
        let pathPattern = #"(?:~?\.{0,2}/[\w\-./]+(?:\.\w+)?|[\w\-]+/[\w\-./]+(?:\.\w+)?)"#
        
        guard let regex = try? NSRegularExpression(pattern: pathPattern, options: []) else {
            return result
        }
        
        // Find all matches in reverse order (so we can replace without index shifting)
        let nsRange = NSRange(result.startIndex..<result.endIndex, in: result)
        let matches = regex.matches(in: result, options: [], range: nsRange)
        
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let path = String(result[range])
            
            // Skip very short paths that might be false positives
            guard path.count >= 3 else { continue }
            
            // Extract basename (last component after /)
            let basename = extractBasename(from: path)
            
            // Skip if basename is empty or same as full path (no slash found)
            guard !basename.isEmpty, basename != path else { continue }
            
            // Replace with spoken form
            let spoken = "file \(basename)"
            result.replaceSubrange(range, with: spoken)
        }
        
        return result
    }
    
    /// Extract the basename (last path component) from a file path.
    private static func extractBasename(from path: String) -> String {
        // Split on / and take the last non-empty component
        let components = path.split(separator: "/")
        guard let last = components.last else { return "" }
        return String(last)
    }
    
    // MARK: - URL Normalization
    
    /// Normalizes URLs to spoken form.
    /// Extracts the domain and announces as "link to [domain]".
    /// - Parameter text: Text that may contain URLs
    /// - Returns: Text with URLs normalized
    static func normalizeURLs(_ text: String) -> String {
        var result = text
        
        // Pattern matches http:// and https:// URLs
        let urlPattern = #"https?://[^\s\]\)>\"']+"#
        
        guard let regex = try? NSRegularExpression(pattern: urlPattern, options: [.caseInsensitive]) else {
            return result
        }
        
        let nsRange = NSRange(result.startIndex..<result.endIndex, in: result)
        let matches = regex.matches(in: result, options: [], range: nsRange)
        
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let urlString = String(result[range])
            
            // Extract domain from URL
            if let domain = extractDomain(from: urlString) {
                let spoken = "link to \(domain)"
                result.replaceSubrange(range, with: spoken)
            }
        }
        
        return result
    }
    
    /// Extract the domain from a URL string.
    private static func extractDomain(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let host = url.host else {
            // Fallback: try simple regex extraction
            let domainPattern = #"https?://([^/\s]+)"#
            guard let regex = try? NSRegularExpression(pattern: domainPattern, options: [.caseInsensitive]) else {
                return nil
            }
            let nsRange = NSRange(urlString.startIndex..<urlString.endIndex, in: urlString)
            guard let match = regex.firstMatch(in: urlString, options: [], range: nsRange),
                  match.numberOfRanges > 1,
                  let domainRange = Range(match.range(at: 1), in: urlString) else {
                return nil
            }
            return String(urlString[domainRange])
        }
        
        // Remove www. prefix for cleaner speech
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return domain
    }
    
    // MARK: - Inline Code Normalization
    
    /// Normalizes inline code (backtick-wrapped content).
    /// Short code is kept and spoken; long code is summarized.
    /// - Parameter text: Text that may contain inline code
    /// - Returns: Text with inline code normalized
    static func normalizeInlineCode(_ text: String) -> String {
        var result = text
        
        // Pattern matches single backtick inline code: `code here`
        // Does NOT match triple backticks (those are code blocks handled elsewhere)
        let codePattern = #"`([^`]+)`"#
        
        guard let regex = try? NSRegularExpression(pattern: codePattern, options: []) else {
            return result
        }
        
        let nsRange = NSRange(result.startIndex..<result.endIndex, in: result)
        let matches = regex.matches(in: result, options: [], range: nsRange)
        
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  match.numberOfRanges > 1,
                  let contentRange = Range(match.range(at: 1), in: result) else { continue }
            
            let content = String(result[contentRange])
            
            // Decide how to handle based on content
            let spoken = normalizeCodeContent(content)
            result.replaceSubrange(fullRange, with: spoken)
        }
        
        return result
    }
    
    /// Normalize code content based on what it appears to be.
    private static func normalizeCodeContent(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        
        // Check if it looks like a shell command FIRST (before length check)
        // This ensures commands like `npm install` get proper "command" prefix
        let shellCommands = ["npm", "yarn", "pnpm", "git", "cd", "ls", "cat", "mkdir", "rm", "cp", "mv", "brew", "apt", "sudo", "chmod", "chown", "curl", "wget", "scp"]
        let firstWord = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
        if shellCommands.contains(firstWord.lowercased()) {
            // For short commands, say "command" + the command
            if trimmed.count <= 30 {
                return "command \(makePronounceable(trimmed))"
            }
            // For long commands, just say the command name
            return "command \(firstWord)"
        }
        
        // Very short code (variable names, etc.) - speak directly
        if trimmed.count <= 15 {
            // Add spaces around special characters for better pronunciation
            return makePronounceable(trimmed)
        }
        
        // Longer code - just make it pronounceable
        return makePronounceable(trimmed)
    }
    
    /// Make a string more pronounceable by TTS.
    /// Adds spaces around special characters and handles common patterns.
    private static func makePronounceable(_ text: String) -> String {
        var result = text
        
        // Replace underscores with spaces
        result = result.replacingOccurrences(of: "_", with: " ")
        
        // Replace hyphens with spaces (for package names like @scope/package-name)
        result = result.replacingOccurrences(of: "-", with: " ")
        
        // Add space before @ symbols
        result = result.replacingOccurrences(of: "@", with: "at ")
        
        // Replace forward slashes with "slash" for clarity in code (but not paths - those are handled separately)
        // Only do this for short strings that look like code, not paths
        if !result.hasPrefix("/") && !result.hasPrefix("./") && !result.hasPrefix("~/") {
            result = result.replacingOccurrences(of: "/", with: " slash ")
        }
        
        // Clean up multiple spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        
        return result.trimmingCharacters(in: .whitespaces)
    }
    
    // MARK: - Environment Variable Normalization
    
    /// Normalizes environment variables to spoken form.
    /// Converts $VAR_NAME or ${VAR_NAME} to "variable VAR NAME".
    /// - Parameter text: Text that may contain environment variables
    /// - Returns: Text with environment variables normalized
    static func normalizeEnvironmentVariables(_ text: String) -> String {
        var result = text
        
        // Pattern matches $VAR_NAME or ${VAR_NAME}
        let envPattern = #"\$\{?([A-Z][A-Z0-9_]*)\}?"#
        
        guard let regex = try? NSRegularExpression(pattern: envPattern, options: []) else {
            return result
        }
        
        let nsRange = NSRange(result.startIndex..<result.endIndex, in: result)
        let matches = regex.matches(in: result, options: [], range: nsRange)
        
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  match.numberOfRanges > 1,
                  let nameRange = Range(match.range(at: 1), in: result) else { continue }
            
            let varName = String(result[nameRange])
            
            // Convert VAR_NAME to "variable var name" (lowercase, spaces instead of underscores)
            let spoken = "variable \(varName.replacingOccurrences(of: "_", with: " ").lowercased())"
            result.replaceSubrange(fullRange, with: spoken)
        }
        
        return result
    }
}
