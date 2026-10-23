// apple-fm: prompt Apple's on-device Foundation Model from the shell or as an MCP server.
//
//   fm "prompt"                     one-shot prompt
//   cat log.txt | fm "summarize"    piped text is appended to the prompt
//   fm -f log.txt "what failed?"    file is read locally and appended
//   fm -s "instructions" "prompt"   system instructions
//   fm --mcp                        MCP stdio server (tool: apple_fm_prompt)

import Foundation
import FoundationModels

// The on-device context window is ~4K tokens; leave room for the prompt and the answer.
let maxInputChars = 9_000

enum FMError: LocalizedError {
    case unavailable(String)
    case unreadable(String)
    var errorDescription: String? {
        switch self {
        case .unavailable(let why): return "Apple on-device model unavailable: \(why)"
        case .unreadable(let path): return "Cannot read file: \(path)"
        }
    }
}

func buildPrompt(_ prompt: String, attached: String?, label: String) -> String {
    guard var text = attached, !text.isEmpty else { return prompt }
    var note = ""
    if text.count > maxInputChars {
        text = String(text.prefix(maxInputChars))
        note = "\n[input truncated to first \(maxInputChars) characters]"
    }
    return "\(prompt)\n\n--- \(label) ---\n\(text)\(note)"
}

func generate(prompt: String, instructions: String?, temperature: Double?) async throws -> String {
    let model = SystemLanguageModel.default
    guard case .available = model.availability else {
        throw FMError.unavailable(String(describing: model.availability))
    }
    let session = instructions.map { LanguageModelSession(instructions: $0) } ?? LanguageModelSession()
    let options = GenerationOptions(temperature: temperature)
    return try await session.respond(to: prompt, options: options).content
}

func readFile(_ path: String) throws -> String {
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw FMError.unreadable(path) }
    return text
}

// MARK: - CLI

func runCLI(_ args: [String]) async -> Int32 {
    var instructions: String?
    var file: String?
    var words: [String] = []
    var it = args.makeIterator()
    while let a = it.next() {
        switch a {
        case "-s", "--instructions": instructions = it.next()
        case "-f", "--file": file = it.next()
        case "-h", "--help":
            print("usage: fm [-s instructions] [-f file] prompt   |   fm --mcp")
            return 0
        default: words.append(a)
        }
    }
    do {
        var attached: String?
        var label = "input"
        if let file {
            attached = try readFile(file)
            label = (file as NSString).lastPathComponent
        } else if isatty(STDIN_FILENO) == 0 {
            attached = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8)
        }
        var prompt = words.joined(separator: " ")
        if prompt.isEmpty, let a = attached { prompt = a; attached = nil }
        guard !prompt.isEmpty else {
            fputs("fm: no prompt given (try fm --help)\n", stderr)
            return 2
        }
        print(try await generate(prompt: buildPrompt(prompt, attached: attached, label: label),
                                 instructions: instructions, temperature: nil))
        return 0
    } catch {
        fputs("fm: \(error.localizedDescription)\n", stderr)
        return 1
    }
}

// MARK: - MCP (stdio, newline-delimited JSON-RPC 2.0)

let toolSchema: [String: Any] = [
    "name": "apple_fm_prompt",
    "description": """
        Run a prompt on Apple's free, on-device Foundation Model (~3B params, ~4K token context). \
        Good for summarizing, classifying, extracting or rewriting short text. Weak at reasoning, \
        code and world knowledge. Pass file_path to have the file read locally so its contents \
        never enter your context (input over ~9,000 characters is truncated).
        """,
    "inputSchema": [
        "type": "object",
        "properties": [
            "prompt": ["type": "string", "description": "The task or question"],
            "instructions": ["type": "string", "description": "Optional system instructions"],
            "file_path": ["type": "string", "description": "Optional absolute path of a text file to read locally and append to the prompt"],
            "temperature": ["type": "number", "description": "Optional sampling temperature, 0 to 2"],
        ],
        "required": ["prompt"],
    ],
]

func send(_ obj: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes]) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

func callTool(_ args: [String: Any]) async -> [String: Any] {
    func result(_ text: String, error: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": error]
    }
    guard let prompt = args["prompt"] as? String, !prompt.isEmpty else {
        return result("Missing required argument: prompt", error: true)
    }
    do {
        var attached: String?
        var label = "input"
        if let path = args["file_path"] as? String, !path.isEmpty {
            attached = try readFile(path)
            label = (path as NSString).lastPathComponent
        }
        let text = try await generate(prompt: buildPrompt(prompt, attached: attached, label: label),
                                      instructions: args["instructions"] as? String,
                                      temperature: (args["temperature"] as? NSNumber)?.doubleValue)
        return result(text, error: false)
    } catch {
        return result(error.localizedDescription, error: true)
    }
}

func runMCP() async {
    while let line = readLine(strippingNewline: true) {
        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let method = msg["method"] as? String
        else { continue }
        guard let id = msg["id"] else { continue }  // notifications need no reply
        let params = msg["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            send(["jsonrpc": "2.0", "id": id, "result": [
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "apple-fm", "version": "1.0.0"],
            ]])
        case "ping":
            send(["jsonrpc": "2.0", "id": id, "result": [:]])
        case "tools/list":
            send(["jsonrpc": "2.0", "id": id, "result": ["tools": [toolSchema]]])
        case "tools/call" where params["name"] as? String == "apple_fm_prompt":
            let res = await callTool(params["arguments"] as? [String: Any] ?? [:])
            send(["jsonrpc": "2.0", "id": id, "result": res])
        default:
            send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Unknown method: \(method)"]])
        }
    }
}

@main
struct FM {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.first == "--mcp" {
            await runMCP()
        } else {
            exit(await runCLI(args))
        }
    }
}
