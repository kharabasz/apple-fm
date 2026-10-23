---
name: apple-fm
description: Send a prompt to Apple's on-device Foundation Model and show its answer.
argument-hint: <prompt> [file path]
disable-model-invocation: true
allowed-tools: mcp__apple-fm__apple_fm_prompt, Bash(fm:*)
---

The user's prompt: $ARGUMENTS

1. If the prompt is empty, ask what to send and stop.
2. Call `mcp__apple-fm__apple_fm_prompt` with the prompt as `prompt`. When the prompt names a file, pass its absolute path as `file_path` and drop the path from `prompt`, so the tool reads the file locally and its contents stay out of your context. When the MCP tool is missing from this session, run the CLI instead: `fm -f <path> "<prompt>"` (or `fm "<prompt>"` with no file), quoting the prompt for the shell.
3. Done when your reply is the model's answer, verbatim, under the heading **Apple on-device model:**. If the call failed, show the error message and stop.
