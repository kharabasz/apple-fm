# apple-fm

Prompt Apple's on-device Foundation Model from the shell, or from Claude Code (or any MCP client) as a tool.

The model is free, runs offline, and keeps data on your Mac. It is small (~3B parameters, ~4K token context), so it suits summarizing, classifying, extracting and rewriting short text, not reasoning or code.

## Requirements

- macOS 26 or later on Apple Silicon
- Apple Intelligence turned on (System Settings → Apple Intelligence & Siri)
- Swift 6 (Xcode 26 or the Command Line Tools)

## Build

```bash
swiftc -O -parse-as-library main.swift -o ~/.local/bin/fm
```

Any directory on your `PATH` works in place of `~/.local/bin`.

## Shell usage

```bash
fm "Name three car parts"
cat build.log | fm "List the errors as bullets"
fm -f build.log -s "Be terse" "What failed?"
```

| Flag | Meaning |
| --- | --- |
| `-s`, `--instructions` | System instructions |
| `-f`, `--file` | Read a file and append it to the prompt |
| `--mcp` | Run as an MCP stdio server |

Piped or file input over 9,000 characters is truncated to fit the context window.

## Claude Code

Register it as a user-scoped MCP server:

```bash
claude mcp add --scope user apple-fm -- ~/.local/bin/fm --mcp
```

New sessions get an `apple_fm_prompt` tool with these arguments:

- `prompt` (required)
- `instructions`, `temperature` (optional)
- `file_path` (optional): the file is read locally, so its contents never enter Claude's context

To remove it:

```bash
claude mcp remove apple-fm -s user
```

## License

[MIT](LICENSE)
