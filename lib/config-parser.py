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
PACKAGE_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9+._-]*$")

ALLOWED_TOP = {"defaults", "token_refresh", "github_app", "chrome", "features", "security", "agents"}
ALLOWED_DEFAULTS = {
    "agents",
    "sandbox",
    "network",
    "workspace",
    "safety_mode",
    "docker_image_prefix",
    "auth_passthrough",
    "default_branch",
}
ALLOWED_TOKEN_REFRESH = {
    "enabled",
    "lead_time",
    "failure_retry_window",
    "retry_backoff",
    "retry_initial_interval",
    "retry_max_interval",
    "cache_github_app_secrets",
}
ALLOWED_GITHUB_APP = {
    "app_id_ref",
    "private_key_ref",
    "installation_strategy",
    "installation_id_ref",
    "installation_id_map",
}
ALLOWED_CHROME = {"profiles_dir", "profile_directory"}
ALLOWED_FEATURES = {
    "packages",
    "mounts",
}
ALLOWED_SECURITY = {"protected_paths", "seccomp_profile", "auth_mount_mode"}
ALLOWED_SECURITY_AUTH_MOUNT_MODE = {
    "codex_dot_codex",
    "claude_dot_claude",
    "claude_config",
    "claude_state",
    "claude_share",
    "claude_cache",
}
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
        "workspace": defaults_raw.get("workspace", "auto"),
        "safety_mode": defaults_raw.get("safety_mode", "safe"),
        "docker_image_prefix": defaults_raw.get("docker_image_prefix", "garth"),
        "auth_passthrough": defaults_raw.get("auth_passthrough", []),
        "default_branch": defaults_raw.get("default_branch", ""),
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
    if not isinstance(defaults["workspace"], str):
        out.error("defaults.workspace must be a string (for example: auto, 3)")
    if defaults["safety_mode"] not in {"safe", "permissive"}:
        out.error("defaults.safety_mode must be one of: safe, permissive")

    if not isinstance(defaults["docker_image_prefix"], str) or not defaults["docker_image_prefix"]:
        out.error("defaults.docker_image_prefix must be a non-empty string")
    if not isinstance(defaults["auth_passthrough"], list):
        out.error("defaults.auth_passthrough must be an array of agent names")
    else:
        for item in defaults["auth_passthrough"]:
            if not isinstance(item, str) or not item.strip():
                out.error("defaults.auth_passthrough entries must be non-empty strings")
    if not isinstance(defaults["default_branch"], str):
        out.error("defaults.default_branch must be a string")

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
        "cache_github_app_secrets": token_raw.get("cache_github_app_secrets", False),
    }

    if not isinstance(token_refresh["enabled"], bool):
        out.error("token_refresh.enabled must be true or false")
    validate_duration(token_refresh["lead_time"], "token_refresh.lead_time", out)
    validate_duration(token_refresh["failure_retry_window"], "token_refresh.failure_retry_window", out)
    validate_duration(token_refresh["retry_initial_interval"], "token_refresh.retry_initial_interval", out)
    validate_duration(token_refresh["retry_max_interval"], "token_refresh.retry_max_interval", out)
    if token_refresh["retry_backoff"] not in {"exponential", "fixed"}:
        out.error("token_refresh.retry_backoff must be one of: exponential, fixed")
    if not isinstance(token_refresh["cache_github_app_secrets"], bool):
        out.error("token_refresh.cache_github_app_secrets must be true or false")

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
        ),
        "profile_directory": chrome_raw.get("profile_directory", ""),
    }
    if not isinstance(chrome["profiles_dir"], str):
        out.error("chrome.profiles_dir must be a string")
    if not isinstance(chrome["profile_directory"], str):
        out.error("chrome.profile_directory must be a string")
    norm["chrome"] = chrome

    features_raw = raw.get("features", {})
    if not isinstance(features_raw, dict):
        out.error("features must be a table")
        features_raw = {}
    for key in features_raw:
        if key not in ALLOWED_FEATURES:
            out.error(f"Unknown key: features.{key}")

    packages: list[str] = []
    packages_seen: set[str] = set()
    packages_raw = features_raw.get("packages")
    if packages_raw is None:
        packages_raw = []
    if not isinstance(packages_raw, list):
        out.error("features.packages must be an array of package names")
    else:
        for idx, item in enumerate(packages_raw):
            field = f"features.packages[{idx}]"
            if not isinstance(item, str) or not item.strip():
                out.error(f"{field} must be a non-empty string")
                continue
            pkg = item.strip().lower()
            if not PACKAGE_NAME_RE.match(pkg):
                out.error(
                    f"{field} must match {PACKAGE_NAME_RE.pattern} "
                    "(lowercase package names only)"
                )
                continue
            if pkg not in packages_seen:
                packages.append(pkg)
                packages_seen.add(pkg)

    mounts: list[dict[str, str]] = []
    mounts_seen: set[tuple[str, str, str]] = set()
    mounts_raw = features_raw.get("mounts")
    if mounts_raw is None:
        mounts_raw = []
    if not isinstance(mounts_raw, list):
        out.error("features.mounts must be an array")
    else:
        for idx, item in enumerate(mounts_raw):
            field = f"features.mounts[{idx}]"
            host_path = ""
            container_path = ""
            mode = "ro"
            if isinstance(item, str):
                host_path = item.strip()
                if not host_path:
                    out.error(f"{field} must be a non-empty path string")
                    continue
            elif isinstance(item, dict):
                for key in item:
                    if key not in {"host_path", "container_path", "mode"}:
                        out.warn(f"Unknown key: {field}.{key}")
                host_val = item.get("host_path", "")
                if not isinstance(host_val, str) or not host_val.strip():
                    out.error(f"{field}.host_path is required and must be a non-empty string")
                    continue
                host_path = host_val.strip()
                container_val = item.get("container_path", "")
                if container_val is None:
                    container_val = ""
                if not isinstance(container_val, str):
                    out.error(f"{field}.container_path must be a string when set")
                    continue
                container_path = container_val.strip()
                mode_val = item.get("mode", "ro")
                if not isinstance(mode_val, str):
                    out.error(f"{field}.mode must be a string")
                    continue
                mode = mode_val.strip().lower()
                if mode not in {"ro", "rw"}:
                    out.error(f"{field}.mode must be one of: ro, rw")
                    continue
            else:
                out.error(f"{field} must be a string path or table")
                continue

            key = (host_path, container_path, mode)
            if key in mounts_seen:
                continue
            mounts_seen.add(key)
            mounts.append(
                {
                    "host_path": host_path,
                    "container_path": container_path,
                    "mode": mode,
                }
            )

    features = {
        "packages": packages,
        "mounts": mounts,
    }
    norm["features"] = features

    security_raw = raw.get("security", {})
    if not isinstance(security_raw, dict):
        out.error("security must be a table")
        security_raw = {}
    warn_unknown_keys(security_raw, ALLOWED_SECURITY, "security.", out)

    auth_mount_mode_raw = security_raw.get("auth_mount_mode", {})
    if not isinstance(auth_mount_mode_raw, dict):
        out.error("security.auth_mount_mode must be a table")
        auth_mount_mode_raw = {}
    warn_unknown_keys(auth_mount_mode_raw, ALLOWED_SECURITY_AUTH_MOUNT_MODE, "security.auth_mount_mode.", out)

    security = {
        "protected_paths": security_raw.get("protected_paths", [".git/hooks", ".git/config", ".github", ".gitmodules"]),
        "seccomp_profile": security_raw.get("seccomp_profile", "docker/seccomp-profile.json"),
        "auth_mount_mode": {
            "codex_dot_codex": auth_mount_mode_raw.get("codex_dot_codex", "rw"),
            "claude_dot_claude": auth_mount_mode_raw.get("claude_dot_claude", "rw"),
            "claude_config": auth_mount_mode_raw.get("claude_config", "rw"),
            "claude_state": auth_mount_mode_raw.get("claude_state", "rw"),
            "claude_share": auth_mount_mode_raw.get("claude_share", "ro"),
            "claude_cache": auth_mount_mode_raw.get("claude_cache", "rw"),
        },
    }

    if not isinstance(security["protected_paths"], list) or not all(
        isinstance(v, str) and bool(v.strip()) for v in security["protected_paths"]
    ):
        out.error("security.protected_paths must be an array of non-empty strings")
    if not isinstance(security["seccomp_profile"], str):
        out.error("security.seccomp_profile must be a string")
    for mode_key, mode_value in security["auth_mount_mode"].items():
        if mode_value not in {"ro", "rw"}:
            out.error(f"security.auth_mount_mode.{mode_key} must be one of: ro, rw")

    norm["security"] = security

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
    features = config["features"]
    security = config["security"]
    agents = config["agents"]

    put("GARTH_DEFAULTS_AGENTS_CSV", ",".join(defaults["agents"]))
    put("GARTH_DEFAULTS_SANDBOX", defaults["sandbox"])
    put("GARTH_DEFAULTS_NETWORK", defaults["network"])
    put("GARTH_DEFAULTS_WORKSPACE", defaults["workspace"])
    put("GARTH_DEFAULTS_SAFETY_MODE", defaults["safety_mode"])
    put("GARTH_DEFAULTS_DOCKER_IMAGE_PREFIX", defaults["docker_image_prefix"])
    put("GARTH_DEFAULTS_AUTH_PASSTHROUGH_CSV", ",".join(defaults["auth_passthrough"]))
    put("GARTH_DEFAULTS_DEFAULT_BRANCH", defaults["default_branch"])

    put("GARTH_TOKEN_REFRESH_ENABLED", token["enabled"])
    put("GARTH_TOKEN_REFRESH_LEAD_TIME", token["lead_time"])
    put("GARTH_TOKEN_REFRESH_FAILURE_RETRY_WINDOW", token["failure_retry_window"])
    put("GARTH_TOKEN_REFRESH_RETRY_BACKOFF", token["retry_backoff"])
    put("GARTH_TOKEN_REFRESH_RETRY_INITIAL_INTERVAL", token["retry_initial_interval"])
    put("GARTH_TOKEN_REFRESH_RETRY_MAX_INTERVAL", token["retry_max_interval"])
    put("GARTH_TOKEN_REFRESH_CACHE_GITHUB_APP_SECRETS", token["cache_github_app_secrets"])

    put("GARTH_GITHUB_APP_APP_ID_REF", gh["app_id_ref"])
    put("GARTH_GITHUB_APP_PRIVATE_KEY_REF", gh["private_key_ref"])
    put("GARTH_GITHUB_APP_INSTALLATION_STRATEGY", gh["installation_strategy"])
    put("GARTH_GITHUB_APP_INSTALLATION_ID_REF", gh["installation_id_ref"])
    put("GARTH_GITHUB_APP_INSTALLATION_ID_MAP_JSON", gh["installation_id_map"])

    put("GARTH_CHROME_PROFILES_DIR", chrome["profiles_dir"])
    put("GARTH_CHROME_PROFILE_DIRECTORY", chrome["profile_directory"])
    put("GARTH_FEATURES_PACKAGES_JSON", features["packages"])
    put("GARTH_FEATURES_MOUNTS_JSON", features["mounts"])

    put("GARTH_SECURITY_PROTECTED_PATHS_JSON", security["protected_paths"])
    put("GARTH_SECURITY_SECCOMP_PROFILE", security["seccomp_profile"])
    for mode_key, mode_value in sorted(security["auth_mount_mode"].items()):
        env_key = NAME_RE.sub("_", mode_key).upper()
        put(f"GARTH_SECURITY_AUTH_MOUNT_MODE_{env_key}", mode_value)

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
