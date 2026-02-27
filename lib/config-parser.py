#!/usr/bin/env python3
"""Parse and validate garth TOML config, then emit shell-safe env values."""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import sys
from pathlib import Path
from typing import Any

if sys.version_info < (3, 11):
    for candidate in ("python3.12", "python3.11"):
        candidate_path = shutil.which(candidate)
        if candidate_path and os.path.realpath(candidate_path) != os.path.realpath(sys.executable):
            os.execv(candidate_path, [candidate_path, *sys.argv])

try:
    import tomllib  # Python 3.11+
except ModuleNotFoundError:
    try:
        import tomli as tomllib
    except ModuleNotFoundError:
        print(
            "error: no TOML parser available (need Python 3.11+ or tomli installed)",
            file=sys.stderr,
        )
        sys.exit(1)

DURATION_RE = re.compile(r"^(?:[0-9]+[smh]|forever)$")
NAME_RE = re.compile(r"[^A-Za-z0-9]")

ALLOWED_TOP = {"defaults", "token_refresh", "github_app", "chrome", "agents"}
ALLOWED_DEFAULTS = {
    "agents",
    "sandbox",
    "network",
    "safety_mode",
    "docker_image_prefix",
}
ALLOWED_TOKEN_REFRESH = {
    "enabled",
    "lead_time",
    "failure_retry_window",
    "retry_backoff",
    "retry_initial_interval",
    "retry_max_interval",
}
ALLOWED_GITHUB_APP = {
    "app_id_ref",
    "private_key_ref",
    "installation_strategy",
    "installation_id_ref",
    "installation_id_map",
}
ALLOWED_CHROME = {"profiles_dir"}
ALLOWED_AGENT = {
    "base_command",
    "command",  # Back-compat input form.
    "safe_args",
    "permissive_args",
    "api_key_env",
    "api_key_ref",
}


class ValidationResult:
    def __init__(self) -> None:
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, msg: str) -> None:
        self.errors.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)

    def ok(self) -> bool:
        return not self.errors


def load_toml(path: Path) -> dict[str, Any]:
    with path.open("rb") as f:
        data = tomllib.load(f)
    if not isinstance(data, dict):
        raise ValueError("Config root must be a TOML table")
    return data


def validate_duration(value: Any, field: str, out: ValidationResult) -> None:
    if not isinstance(value, str) or not DURATION_RE.match(value):
        out.error(f"{field} must be a duration like 5s, 10m, 2h, 0m, or forever")


def require_str(table: dict[str, Any], key: str, field: str, out: ValidationResult) -> None:
    value = table.get(key)
    if not isinstance(value, str) or not value.strip():
        out.error(f"{field} is required and must be a non-empty string")


def warn_unknown_keys(table: dict[str, Any], allowed: set[str], prefix: str, out: ValidationResult) -> None:
    for key in table:
        if key not in allowed:
            out.warn(f"Unknown key: {prefix}{key}")


def normalize_config(raw: dict[str, Any], out: ValidationResult) -> dict[str, Any]:
    norm: dict[str, Any] = {}

    for key in raw:
        if key not in ALLOWED_TOP:
            out.warn(f"Unknown top-level key: {key}")

    defaults_raw = raw.get("defaults", {})
    if not isinstance(defaults_raw, dict):
        out.error("defaults must be a table")
        defaults_raw = {}
    warn_unknown_keys(defaults_raw, ALLOWED_DEFAULTS, "defaults.", out)

    defaults = {
        "agents": defaults_raw.get("agents", ["claude", "codex"]),
        "sandbox": defaults_raw.get("sandbox", "docker"),
        "network": defaults_raw.get("network", "bridge"),
        "safety_mode": defaults_raw.get("safety_mode", "safe"),
        "docker_image_prefix": defaults_raw.get("docker_image_prefix", "garth"),
    }

    if not isinstance(defaults["agents"], list) or not defaults["agents"]:
        out.error("defaults.agents must be a non-empty array")
    else:
        for item in defaults["agents"]:
            if not isinstance(item, str) or not item.strip():
                out.error("defaults.agents entries must be non-empty strings")

    if defaults["sandbox"] not in {"docker", "none"}:
        out.error("defaults.sandbox must be one of: docker, none")
    if defaults["network"] not in {"bridge", "none"}:
        out.error("defaults.network must be one of: bridge, none")
    if defaults["safety_mode"] not in {"safe", "permissive"}:
        out.error("defaults.safety_mode must be one of: safe, permissive")

    if not isinstance(defaults["docker_image_prefix"], str) or not defaults["docker_image_prefix"]:
        out.error("defaults.docker_image_prefix must be a non-empty string")

    norm["defaults"] = defaults

    token_raw = raw.get("token_refresh", {})
    if not isinstance(token_raw, dict):
        out.error("token_refresh must be a table")
        token_raw = {}
    warn_unknown_keys(token_raw, ALLOWED_TOKEN_REFRESH, "token_refresh.", out)

    token_refresh = {
        "enabled": token_raw.get("enabled", True),
        "lead_time": token_raw.get("lead_time", "15m"),
        "failure_retry_window": token_raw.get("failure_retry_window", "10m"),
        "retry_backoff": token_raw.get("retry_backoff", "exponential"),
        "retry_initial_interval": token_raw.get("retry_initial_interval", "5s"),
        "retry_max_interval": token_raw.get("retry_max_interval", "60s"),
    }

    if not isinstance(token_refresh["enabled"], bool):
        out.error("token_refresh.enabled must be true or false")
    validate_duration(token_refresh["lead_time"], "token_refresh.lead_time", out)
    validate_duration(token_refresh["failure_retry_window"], "token_refresh.failure_retry_window", out)
    validate_duration(token_refresh["retry_initial_interval"], "token_refresh.retry_initial_interval", out)
    validate_duration(token_refresh["retry_max_interval"], "token_refresh.retry_max_interval", out)
    if token_refresh["retry_backoff"] not in {"exponential", "fixed"}:
        out.error("token_refresh.retry_backoff must be one of: exponential, fixed")

    norm["token_refresh"] = token_refresh

    gh_raw = raw.get("github_app", {})
    if not isinstance(gh_raw, dict):
        out.error("github_app must be a table")
        gh_raw = {}
    warn_unknown_keys(gh_raw, ALLOWED_GITHUB_APP, "github_app.", out)

    github_app = {
        "app_id_ref": gh_raw.get("app_id_ref", ""),
        "private_key_ref": gh_raw.get("private_key_ref", ""),
        "installation_strategy": gh_raw.get("installation_strategy", "by_owner"),
        "installation_id_ref": gh_raw.get("installation_id_ref", ""),
        "installation_id_map": gh_raw.get("installation_id_map", {}),
    }

    require_str(github_app, "app_id_ref", "github_app.app_id_ref", out)
    require_str(github_app, "private_key_ref", "github_app.private_key_ref", out)
    if github_app["installation_strategy"] not in {"by_owner", "static_map", "single"}:
        out.error("github_app.installation_strategy must be one of: by_owner, static_map, single")

    if github_app["installation_strategy"] == "single":
        if not isinstance(github_app["installation_id_ref"], str) or not github_app["installation_id_ref"].strip():
            out.error("github_app.installation_id_ref is required when installation_strategy=single")

    if github_app["installation_strategy"] == "static_map":
        if not isinstance(github_app["installation_id_map"], dict) or not github_app["installation_id_map"]:
            out.error("github_app.installation_id_map must be a non-empty table when installation_strategy=static_map")

    if not isinstance(github_app["installation_id_map"], dict):
        out.error("github_app.installation_id_map must be a table")
        github_app["installation_id_map"] = {}

    norm["github_app"] = github_app

    chrome_raw = raw.get("chrome", {})
    if not isinstance(chrome_raw, dict):
        out.error("chrome must be a table")
        chrome_raw = {}
    warn_unknown_keys(chrome_raw, ALLOWED_CHROME, "chrome.", out)

    chrome = {
        "profiles_dir": chrome_raw.get(
            "profiles_dir",
            "~/Library/Application Support/Chrome-ProjectProfiles",
        )
    }
    if not isinstance(chrome["profiles_dir"], str) or not chrome["profiles_dir"].strip():
        out.error("chrome.profiles_dir must be a non-empty string")
    norm["chrome"] = chrome

    agents_raw = raw.get("agents", {})
    if not isinstance(agents_raw, dict) or not agents_raw:
        out.error("agents must be a non-empty table")
        agents_raw = {}

    agents: dict[str, dict[str, Any]] = {}
    for name, table in agents_raw.items():
        if not isinstance(table, dict):
            out.error(f"agents.{name} must be a table")
            continue
        warn_unknown_keys(table, ALLOWED_AGENT, f"agents.{name}.", out)

        base_command = table.get("base_command")
        if not base_command:
            base_command = table.get("command", "")

        agent = {
            "base_command": base_command,
            "safe_args": table.get("safe_args", []),
            "permissive_args": table.get("permissive_args", []),
            "api_key_env": table.get("api_key_env", ""),
            "api_key_ref": table.get("api_key_ref", ""),
        }

        if not isinstance(agent["base_command"], str) or not agent["base_command"].strip():
            out.error(f"agents.{name}.base_command is required and must be non-empty")

        for arg_field in ("safe_args", "permissive_args"):
            value = agent[arg_field]
            if not isinstance(value, list) or not all(isinstance(v, str) for v in value):
                out.error(f"agents.{name}.{arg_field} must be an array of strings")

        if not isinstance(agent["api_key_env"], str) or not agent["api_key_env"].strip():
            out.error(f"agents.{name}.api_key_env is required and must be non-empty")
        if not isinstance(agent["api_key_ref"], str) or not agent["api_key_ref"].strip():
            out.error(f"agents.{name}.api_key_ref is required and must be non-empty")

        agents[name] = agent

    for agent_name in defaults.get("agents", []):
        if agent_name not in agents:
            out.error(f"defaults.agents references missing agents.{agent_name}")

    norm["agents"] = agents
    return norm


def emit_env(config: dict[str, Any]) -> str:
    lines: list[str] = []

    def put(key: str, value: Any) -> None:
        if isinstance(value, bool):
            rendered = "true" if value else "false"
        elif isinstance(value, (dict, list)):
            rendered = json.dumps(value, separators=(",", ":"))
        else:
            rendered = str(value)
        lines.append(f"{key}={shlex.quote(rendered)}")

    defaults = config["defaults"]
    token = config["token_refresh"]
    gh = config["github_app"]
    chrome = config["chrome"]
    agents = config["agents"]

    put("GARTH_DEFAULTS_AGENTS_CSV", ",".join(defaults["agents"]))
    put("GARTH_DEFAULTS_SANDBOX", defaults["sandbox"])
    put("GARTH_DEFAULTS_NETWORK", defaults["network"])
    put("GARTH_DEFAULTS_SAFETY_MODE", defaults["safety_mode"])
    put("GARTH_DEFAULTS_DOCKER_IMAGE_PREFIX", defaults["docker_image_prefix"])

    put("GARTH_TOKEN_REFRESH_ENABLED", token["enabled"])
    put("GARTH_TOKEN_REFRESH_LEAD_TIME", token["lead_time"])
    put("GARTH_TOKEN_REFRESH_FAILURE_RETRY_WINDOW", token["failure_retry_window"])
    put("GARTH_TOKEN_REFRESH_RETRY_BACKOFF", token["retry_backoff"])
    put("GARTH_TOKEN_REFRESH_RETRY_INITIAL_INTERVAL", token["retry_initial_interval"])
    put("GARTH_TOKEN_REFRESH_RETRY_MAX_INTERVAL", token["retry_max_interval"])

    put("GARTH_GITHUB_APP_APP_ID_REF", gh["app_id_ref"])
    put("GARTH_GITHUB_APP_PRIVATE_KEY_REF", gh["private_key_ref"])
    put("GARTH_GITHUB_APP_INSTALLATION_STRATEGY", gh["installation_strategy"])
    put("GARTH_GITHUB_APP_INSTALLATION_ID_REF", gh["installation_id_ref"])
    put("GARTH_GITHUB_APP_INSTALLATION_ID_MAP_JSON", gh["installation_id_map"])

    put("GARTH_CHROME_PROFILES_DIR", chrome["profiles_dir"])

    names = sorted(agents.keys())
    put("GARTH_AGENT_NAMES_CSV", ",".join(names))

    for name in names:
        key = NAME_RE.sub("_", name).upper()
        agent = agents[name]
        put(f"GARTH_AGENT_{key}_BASE_COMMAND", agent["base_command"])
        put(f"GARTH_AGENT_{key}_SAFE_ARGS_JSON", agent["safe_args"])
        put(f"GARTH_AGENT_{key}_PERMISSIVE_ARGS_JSON", agent["permissive_args"])
        put(f"GARTH_AGENT_{key}_API_KEY_ENV", agent["api_key_env"])
        put(f"GARTH_AGENT_{key}_API_KEY_REF", agent["api_key_ref"])

    return "\n".join(lines)


def run_validate(config_path: Path) -> int:
    raw = load_toml(config_path)
    out = ValidationResult()
    normalize_config(raw, out)
    for warning in out.warnings:
        print(f"warning: {warning}", file=sys.stderr)
    for error in out.errors:
        print(f"error: {error}", file=sys.stderr)
    return 0 if out.ok() else 1


def run_env(config_path: Path) -> int:
    raw = load_toml(config_path)
    out = ValidationResult()
    normalized = normalize_config(raw, out)
    for warning in out.warnings:
        print(f"warning: {warning}", file=sys.stderr)
    if not out.ok():
        for error in out.errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    print(emit_env(normalized))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="garth config parser")
    parser.add_argument("command", choices=["validate", "env"])
    parser.add_argument("config", help="Path to config TOML")
    args = parser.parse_args()

    config_path = Path(args.config).expanduser()
    if not config_path.exists():
        print(f"error: config not found: {config_path}", file=sys.stderr)
        return 1

    if args.command == "validate":
        return run_validate(config_path)
    return run_env(config_path)


if __name__ == "__main__":
    sys.exit(main())
