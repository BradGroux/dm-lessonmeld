#!/usr/bin/env python3
"""Minimal stdio MCP wrapper for safe dmlesson JSON commands."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any


PROTOCOL_VERSION = "2025-06-18"
SUPPORTED_PROTOCOLS = {PROTOCOL_VERSION, "2025-03-26"}
REPO_ROOT = Path(__file__).resolve().parents[1]
MAX_OUTPUT_BYTES = int(os.environ.get("DMLESSON_MCP_MAX_OUTPUT_BYTES", "131072"))
DISCLOSURE_POLICY_ENV = "DMLESSON_MCP_ALLOW_DISCLOSURE"
ABSOLUTE_PATH_PATTERN = re.compile(
    r"(?<![:/A-Za-z0-9._-])/(?:[^/\s:]+/)*[^\s,;:)\]}\"']+"
)


class ToolError(Exception):
    pass


@dataclass
class CommandResult:
    returncode: int
    stdout: str
    stderr: str
    stdout_truncated: bool = False
    stderr_truncated: bool = False


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
        except Exception as error:  # noqa: BLE001 - keep stdio server alive on malformed JSON.
            response = error_response(None, -32700, str(error))
        else:
            response = handle_message(message)
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
    disclosure_denied = handle_message(
        {
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": {
                "name": "dmlesson_agent_manifest",
                "arguments": {"project": "/tmp/lesson.dmlm", "includeMediaPaths": True},
            },
        }
    )
    with tempfile.TemporaryDirectory(prefix="dm-lessonmeld-mcp-test.") as temp_dir:
        slow_cli = Path(temp_dir) / "slow-dmlesson"
        slow_cli.write_text("#!/bin/sh\nsleep 1\necho '{}'\n", encoding="utf-8")
        slow_cli.chmod(0o700)
        old_cli = os.environ.get("DMLESSON_CLI")
        old_timeout = os.environ.get("DMLESSON_MCP_TIMEOUT")
        os.environ["DMLESSON_CLI"] = str(slow_cli)
        os.environ["DMLESSON_MCP_TIMEOUT"] = "0.01"
        try:
            timeout_result = handle_message(
                {
                    "jsonrpc": "2.0",
                    "id": 5,
                    "method": "tools/call",
                    "params": {"name": "dmlesson_project_inspect", "arguments": {"project": "/tmp/lesson.dmlm"}},
                }
            )
        finally:
            restore_env("DMLESSON_CLI", old_cli)
            restore_env("DMLESSON_MCP_TIMEOUT", old_timeout)
    with tempfile.TemporaryFile() as output_file:
        output_file.write(b"x" * (MAX_OUTPUT_BYTES + 1))
        oversized_output, oversized_truncated = read_limited_output(output_file, MAX_OUTPUT_BYTES)
    assert initialize and initialize["result"]["capabilities"]["tools"]["listChanged"] is False
    assert tools and len(tools["result"]["tools"]) >= 5
    assert workflow and workflow["result"]["isError"] is False
    assert disclosure_denied and disclosure_denied["id"] == 4
    assert disclosure_denied["result"]["isError"] is True
    with tempfile.TemporaryDirectory(prefix="dm-lessonmeld-mcp-redaction-test.") as temp_dir:
        private_project = Path(temp_dir) / "private" / "Secret Lesson.dmlm"
        private_artifact = Path(temp_dir) / "private" / "secret output.json"
        redaction_cli = Path(temp_dir) / "redaction-dmlesson"
        redaction_cli.write_text(
            "#!/usr/bin/env python3\n"
            "import json\n"
            "import sys\n"
            f"artifact = {str(private_artifact)!r}\n"
            "if sys.argv[1:3] == ['project', 'inspect']:\n"
            "    print(f'Project path is not a directory: {sys.argv[3]}.', file=sys.stderr)\n"
            "    raise SystemExit(2)\n"
            "print(json.dumps({'artifactPath': artifact, 'message': f'Created {artifact}'}))\n",
            encoding="utf-8",
        )
        redaction_cli.chmod(0o700)
        old_cli = os.environ.get("DMLESSON_CLI")
        old_disclosure = os.environ.get(DISCLOSURE_POLICY_ENV)
        os.environ["DMLESSON_CLI"] = str(redaction_cli)
        try:
            failed_path_result = handle_message(
                {
                    "jsonrpc": "2.0",
                    "id": 6,
                    "method": "tools/call",
                    "params": {
                        "name": "dmlesson_project_inspect",
                        "arguments": {"project": str(private_project)},
                    },
                }
            )
            structured_path_result = handle_message(
                {
                    "jsonrpc": "2.0",
                    "id": 7,
                    "method": "tools/call",
                    "params": {"name": "dmlesson_agent_workflows", "arguments": {}},
                }
            )
            os.environ[DISCLOSURE_POLICY_ENV] = "1"
            disclosed_path_result = handle_message(
                {
                    "jsonrpc": "2.0",
                    "id": 8,
                    "method": "tools/call",
                    "params": {
                        "name": "dmlesson_agent_manifest",
                        "arguments": {"project": str(private_project), "includeMediaPaths": True},
                    },
                }
            )
            os.environ["DMLESSON_CLI"] = str(Path(temp_dir) / "private" / "missing dmlesson")
            launch_failure_result = handle_message(
                {
                    "jsonrpc": "2.0",
                    "id": 9,
                    "method": "tools/call",
                    "params": {
                        "name": "dmlesson_project_inspect",
                        "arguments": {"project": str(private_project)},
                    },
                }
            )
        finally:
            restore_env("DMLESSON_CLI", old_cli)
            restore_env(DISCLOSURE_POLICY_ENV, old_disclosure)
        assert failed_path_result and failed_path_result["result"]["isError"] is True
        assert temp_dir not in json.dumps(failed_path_result)
        assert structured_path_result and structured_path_result["result"]["isError"] is False
        assert temp_dir not in json.dumps(structured_path_result)
        assert structured_path_result["result"]["structuredContent"]["artifactPath"] == "secret output.json"
        assert disclosed_path_result and disclosed_path_result["result"]["isError"] is False
        assert str(private_artifact) in json.dumps(disclosed_path_result)
        assert launch_failure_result and launch_failure_result["result"]["isError"] is True
        assert temp_dir not in json.dumps(launch_failure_result)
    assert timeout_result and timeout_result["id"] == 5
    assert timeout_result["result"]["isError"] is True
    assert oversized_truncated is True
    assert len(oversized_output) == MAX_OUTPUT_BYTES
    assert redact_local_paths("Read /.private.", []) == "Read .private."
    assert redact_local_paths("See https://example.com/docs.", []) == "See https://example.com/docs."
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
                "serverInfo": {"name": "dm-lessonmeld", "version": "0.0.4"},
                "instructions": "Use read-only LessonMeld tools for project inspection, render planning, and agent workflow discovery.",
            },
        )
    if method == "ping":
        return result_response(request_id, {})
    if method == "tools/list":
        return result_response(request_id, {"tools": TOOLS})
    if method == "tools/call":
        raw_params = message.get("params", {})
        params = raw_params if isinstance(raw_params, dict) else {}
        name = str(params.get("name", ""))
        raw_arguments = params.get("arguments", {}) or {}
        arguments = raw_arguments if isinstance(raw_arguments, dict) else {}
        try:
            result = call_tool(name, arguments)
        except ToolError as error:
            result = {"content": [{"type": "text", "text": str(error)}], "isError": True}
        except Exception as error:  # noqa: BLE001 - preserve JSON-RPC id for tool failures.
            result = {
                "content": [{"type": "text", "text": f"Tool failed: {error}"}],
                "isError": True,
            }
        if not tool_call_allows_path_disclosure(name, arguments):
            sensitive_paths = collect_absolute_paths(arguments) + collect_absolute_paths(result)
            configured_cli = os.environ.get("DMLESSON_CLI")
            if configured_cli and os.path.isabs(configured_cli):
                sensitive_paths.append(configured_cli)
            result = redact_local_paths(
                result,
                sensitive_paths=sensitive_paths,
            )
        return result_response(request_id, result)

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
        include_media_paths = bool(arguments.get("includeMediaPaths", False))
        include_transcript_references = bool(arguments.get("includeTranscriptReferences", False))
        if (include_media_paths or include_transcript_references) and not disclosure_policy_allows_paths():
            raise ToolError(
                f"Media path and transcript disclosure requires {DISCLOSURE_POLICY_ENV}=1 in the MCP host environment."
            )
        if include_media_paths:
            args.append("--include-media-paths")
        if include_transcript_references:
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
    output_text = completed.stdout.strip() if completed.stdout.strip() else completed.stderr.strip()
    if completed.stdout_truncated or completed.stderr_truncated:
        output_text = f"{output_text}\n[output truncated by MCP wrapper]"
    parsed = parse_json(completed.stdout.strip())
    content_text = (
        "Structured JSON response returned."
        if parsed is not None and completed.returncode == 0
        else output_text
    )
    result: dict[str, Any] = {
        "content": [{"type": "text", "text": content_text}],
        "isError": completed.returncode != 0,
    }
    if parsed is not None:
        result["structuredContent"] = parsed if isinstance(parsed, dict) else {"items": parsed}
    return result


def run_dmlesson(args: list[str]) -> CommandResult:
    command = dmlesson_command() + args
    timeout = float(os.environ.get("DMLESSON_MCP_TIMEOUT", "60"))
    with tempfile.TemporaryFile() as stdout_file, tempfile.TemporaryFile() as stderr_file:
        process = subprocess.Popen(
            command,
            cwd=REPO_ROOT,
            stdout=stdout_file,
            stderr=stderr_file,
            text=False,
        )
        timed_out = False
        try:
            returncode = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            process.kill()
            returncode = process.wait()

        stdout, stdout_truncated = read_limited_output(stdout_file, MAX_OUTPUT_BYTES)
        stderr, stderr_truncated = read_limited_output(stderr_file, MAX_OUTPUT_BYTES)
        if timed_out:
            return CommandResult(
                returncode=124,
                stdout=stdout,
                stderr=f"{stderr}\nCommand timed out after {timeout:g} seconds.".strip(),
                stdout_truncated=stdout_truncated,
                stderr_truncated=stderr_truncated,
            )
        return CommandResult(returncode, stdout, stderr, stdout_truncated, stderr_truncated)


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


def disclosure_policy_allows_paths() -> bool:
    return os.environ.get(DISCLOSURE_POLICY_ENV, "").strip().lower() in {"1", "true", "yes"}


def tool_call_allows_path_disclosure(name: str, arguments: dict[str, Any]) -> bool:
    return (
        name == "dmlesson_agent_manifest"
        and disclosure_policy_allows_paths()
        and bool(arguments.get("includeMediaPaths") or arguments.get("includeTranscriptReferences"))
    )


def collect_absolute_paths(value: Any) -> list[str]:
    if isinstance(value, str):
        return [value] if os.path.isabs(value) else []
    if isinstance(value, list):
        return [path for item in value for path in collect_absolute_paths(item)]
    if isinstance(value, dict):
        return [
            path
            for item in (*value.keys(), *value.values())
            for path in collect_absolute_paths(item)
        ]
    return []


def read_limited_output(handle: Any, max_bytes: int) -> tuple[str, bool]:
    handle.seek(0)
    data = handle.read(max_bytes + 1)
    truncated = len(data) > max_bytes
    if truncated:
        data = data[:max_bytes]
    return data.decode("utf-8", errors="replace"), truncated


def restore_env(name: str, value: str | None) -> None:
    if value is None:
        os.environ.pop(name, None)
    else:
        os.environ[name] = value


def redact_local_paths(value: Any, sensitive_paths: list[str]) -> Any:
    if isinstance(value, str):
        redacted = value
        for path in sorted(set(sensitive_paths), key=len, reverse=True):
            redacted = redacted.replace(path, local_path_basename(path))
        if os.path.isabs(redacted):
            return local_path_basename(redacted)
        return ABSOLUTE_PATH_PATTERN.sub(
            lambda match: redact_path_match(match.group(0)),
            redacted,
        )
    if isinstance(value, list):
        return [redact_local_paths(item, sensitive_paths) for item in value]
    if isinstance(value, dict):
        redacted_mapping: dict[Any, Any] = {}
        for key, item in value.items():
            redacted_key = redact_local_paths(key, sensitive_paths) if isinstance(key, str) else key
            redacted_mapping[redacted_key] = redact_local_paths(item, sensitive_paths)
        return redacted_mapping
    return value


def redact_path_match(path: str) -> str:
    suffix = ""
    while path and path[-1] in ".!?":
        suffix = path[-1] + suffix
        path = path[:-1]
    return local_path_basename(path) + suffix


def local_path_basename(path: str) -> str:
    basename = os.path.basename(path.rstrip(os.sep))
    return basename or "[local path redacted]"


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
