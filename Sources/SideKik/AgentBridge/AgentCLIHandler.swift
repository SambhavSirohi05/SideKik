import Foundation

/// Ensures the user-facing CLI script is installed and handles command-line triggers
public final class AgentCLIHandler: Sendable {
    public static let shared = AgentCLIHandler()

    private init() {}

    /// Installs `clickymac` helper script into `~/.local/bin/clickymac`
    public func installCLIToolIfNeeded() {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let localBin = homeDir.appendingPathComponent(".local/bin", isDirectory: true)

        if !fileManager.fileExists(atPath: localBin.path) {
            try? fileManager.createDirectory(at: localBin, withIntermediateDirectories: true)
        }

        let scriptURL = localBin.appendingPathComponent("sidekik")

        let scriptContent = """
        #!/bin/zsh
        # SideKik CLI bridge for Claude Code, Cursor, Antigravity, and terminal agents

        SERVER_URL="http://127.0.0.1:25425"

        case "$1" in
          notify|attention)
            APP="Terminal"
            MSG=""
            TITLE="Agent Alert"
            shift
            while [[ "$#" -gt 0 ]]; do
              case $1 in
                --app) APP="$2"; shift ;;
                --message|-m) MSG="$2"; shift ;;
                --title|-t) TITLE="$2"; shift ;;
              esac
              shift
            done
            curl -s -X POST "$SERVER_URL/attention" \\
              -H "Content-Type: application/json" \\
              -d "{\\"app\\": \\"$APP\\", \\"title\\": \\"$TITLE\\", \\"message\\": \\"$MSG\\"}"
            ;;
          react)
            STATE="${2:-idle}"
            curl -s -X POST "$SERVER_URL/react" \\
              -H "Content-Type: application/json" \\
              -d "{\\"state\\": \\"$STATE\\"}"
            ;;
          say)
            TEXT="$2"
            curl -s -X POST "$SERVER_URL/say" \\
              -H "Content-Type: application/json" \\
              -d "{\\"text\\": \\"$TEXT\\", \\"voice\\": true}"
            ;;
          *)
            echo "Usage: sidekik [notify|react|say] [options]"
            echo "  sidekik notify --app 'Cursor' --message 'Waiting for input'"
            echo "  sidekik react [happy|thinking|alert|idle]"
            echo "  sidekik say 'Task completed!'"
            ;;
        esac
        """

        try? scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)

        // Make executable
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/chmod")
        process.arguments = ["+x", scriptURL.path]
        try? process.run()
        process.waitUntilExit()
    }
}
