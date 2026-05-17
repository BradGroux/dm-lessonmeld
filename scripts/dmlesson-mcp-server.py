#!/usr/bin/env python3
"""Minimal stdio MCP wrapper for safe dmlesson JSON commands."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any


PROTOCOL_VERSION = "2025-06-18"
SUPPORTED_PROTOCOLS = {PROTOCOL_VERSION, "2025-03-26"}
REPO_ROOT = Path(__file__).resolve().parents[1]


class ToolError(Exception):
    pass


TOOLS: list[dict[str, Any]] = [
    {
        "name": "dmlesson_project_inspect",
        "title": "Inspect LessonMeld Project",
        "description": "Validate and summarize a local .dmlm project bundle as stable JSON.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "project": {"type": "string", "description": "Path to a .dmlm project bundle."}
            },
            "required": ["project"],
        },
        "annotations": {"readOnlyHint": True},
    },
    {
        "name": "dmlesson_render_plan",
        "title": "Plan LessonMeld Render",
        "description": "Inspect render readiness without exporting media.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "project": {"type": "string", "description": "Path to a .dmlm project bundle."},
                "output": {"type": "string", "description": "Intended output video path."},
                "resolution": {"type": "string", "description": "Optional render resolution."},
                "fps": {"type": "string", "description": "Optional render frame-rate."},
                "codec": {"type": "string", "description": "Optional render codec."},
            },
            "required": ["project", "output"],
        },
        "annotations": {"readOnlyHint": True},
    },
    {
        "name": "dmlesson_agent_manifest",
        "title": "Read LessonMeld Agent Manifest",
        "description": "Return a redacted agent-readable project manifest.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "project": {"type": "string", "description": "Path to a .dmlm project bundle."},
                "includeMediaPaths": {"type": "boolean", "default": False},
                "includeTranscriptReferences": {"type": "boolean", "default": False},
            },
            "required": ["project"],
        },
        "annotations": {"readOnlyHint": True},
    },
    {
        "name": "dmlesson_agent_workflows",
        "title": "List LessonMeld Agent Workflows",
        "description": "List safe CLI workflow sequences for OpenClaw, Codex, or Veritas Kanban.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "target": {
                    "type": "string",
                    "description": "Optional target: openclaw, codex, or veritas-kanban.",
                }
            },
        },
        "annotations": {"readOnlyHint": True},
    },
    {
        "name": "dmlesson_transcript_model_status",
        "title": "Check LessonMeld Transcription Model",
        "description": "Report local transcription model readiness from default or supplied settings.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "settings": {"type": "string", "description": "Optional settings JSON path."}
            },
        },
        "annotations": {"readOnlyHint": True},
    },
]


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "--self-test":
        return self_test()

    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
            response = handle_message(message)
        except Exception as error:  # noqa: BLE001 - keep stdio server alive on malformed messages.
            response = error_response(None, -32700, str(error))
        if response is not None:
            write_message(response)
    return 0


def self_test() -> int:
    initialize = handle_message(
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {"protocolVersion": PROTOCOL_VERSION, "capabilities": {}, "clientInfo": {"name": "self-test"}},
        }
    )
    tools = handle_message({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
    workflow = handle_message(
        {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {"name": "dmlesson_agent_workflows", "arguments": {"target": "codex"}},
        }
    )
    assert initialize and initialize["result"]["capabilities"]["tools"]["listChanged"] is False
    assert tools and len(tools["result"]["tools"]) >= 5
    assert workflow and workflow["result"]["isError"] is False
    return 0


def handle_message(message: dict[str, Any]) -> dict[str, Any] | None:
    method = message.get("method")
    request_id = message.get("id")

    if method == "notifications/initialized":
        return None
    if method == "initialize":
        requested = str(message.get("params", {}).get("protocolVersion", PROTOCOL_VERSION))
        negotiated = requested if requested in SUPPORTED_PROTOCOLS else PROTOCOL_VERSION
        return result_response(
            request_id,
            {
                "protocolVersion": negotiated,
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": "dm-lessonmeld", "version": "0.0.3"},
                "instructions": "Use read-only LessonMeld tools for project inspection, render planning, and agent workflow discovery.",
            },
        )
    if method == "ping":
        return result_response(request_id, {})
    if method == "tools/list":
        return result_response(request_id, {"tools": TOOLS})
    if method == "tools/call":
        params = message.get("params", {})
        try:
            result = call_tool(str(params.get("name", "")), params.get("arguments", {}) or {})
            return result_response(request_id, result)
        except ToolError as error:
            return result_response(
                request_id,
                {"content": [{"type": "text", "text": str(error)}], "isError": True},
            )

    return error_response(request_id, -32601, f"Method not found: {method}")


def call_tool(name: str, arguments: dict[str, Any]) -> dict[str, Any]:
    if name == "dmlesson_project_inspect":
        args = ["project", "inspect", required_string(arguments, "project"), "--json"]
    elif name == "dmlesson_render_plan":
        args = [
            "render",
            "plan",
            required_string(arguments, "project"),
            "--output",
            required_string(arguments, "output"),
            "--json",
        ]
        append_option(args, "--resolution", arguments.get("resolution"))
        append_option(args, "--fps", arguments.get("fps"))
        append_option(args, "--codec", arguments.get("codec"))
    elif name == "dmlesson_agent_manifest":
        args = ["agent", "manifest", required_string(arguments, "project")]
        if bool(arguments.get("includeMediaPaths", False)):
            args.append("--include-media-paths")
        if bool(arguments.get("includeTranscriptReferences", False)):
            args.append("--include-transcript-references")
    elif name == "dmlesson_agent_workflows":
        args = ["agent", "workflows", "--json"]
        append_option(args, "--target", arguments.get("target"))
    elif name == "dmlesson_transcript_model_status":
        args = ["transcript", "model-status", "--json"]
        append_option(args, "--settings", arguments.get("settings"))
    else:
        raise ToolError(f"Unknown tool: {name}")

    completed = run_dmlesson(args)
    text = completed.stdout.strip() or completed.stderr.strip()
    parsed = parse_json(text)
    result: dict[str, Any] = {
        "content": [{"type": "text", "text": text}],
        "isError": completed.returncode != 0,
    }
    if parsed is not None:
        result["structuredContent"] = parsed if isinstance(parsed, dict) else {"items": parsed}
    return result


def run_dmlesson(args: list[str]) -> subprocess.CompletedProcess[str]:
    command = dmlesson_command() + args
    timeout = float(os.environ.get("DMLESSON_MCP_TIMEOUT", "60"))
    return subprocess.run(
        command,
        cwd=REPO_ROOT,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )


def dmlesson_command() -> list[str]:
    configured = os.environ.get("DMLESSON_CLI")
    if configured:
        return [configured]
    built = REPO_ROOT / ".build" / "debug" / "dmlesson"
    if built.exists() and os.access(built, os.X_OK):
        return [str(built)]
    return ["swift", "run", "dmlesson"]


def required_string(arguments: dict[str, Any], name: str) -> str:
    value = arguments.get(name)
    if not isinstance(value, str) or not value.strip():
        raise ToolError(f"Missing required string argument: {name}")
    return value


def append_option(args: list[str], option: str, value: Any) -> None:
    if value is None:
        return
    text = str(value).strip()
    if text:
        args.extend([option, text])


def parse_json(text: str) -> Any | None:
    if not text:
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return None


def result_response(request_id: Any, result: dict[str, Any]) -> dict[str, Any]:
    return {"jsonrpc": "2.0", "id": request_id, "result": result}


def error_response(request_id: Any, code: int, message: str) -> dict[str, Any]:
    return {"jsonrpc": "2.0", "id": request_id, "error": {"code": code, "message": message}}


def write_message(message: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(message, separators=(",", ":")) + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    raise SystemExit(main())
