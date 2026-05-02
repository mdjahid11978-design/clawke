"""Configuration loader for Clawke Hermes Gateway.

Reads gateway settings from environment variables, ~/.clawke/clawke.json,
or falls back to sensible defaults.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

from clawke_channel import GatewayConfig


def load_config() -> GatewayConfig:
    """Load gateway configuration.

    Priority:
    1. Environment variables (CLAWKE_WS_URL, CLAWKE_ACCOUNT_ID, etc.)
    2. ~/.clawke/clawke.json → accounts.hermes section
    3. Defaults
    """
    config = GatewayConfig()

    # Try loading from clawke.json
    clawke_json = Path.home() / ".clawke" / "clawke.json"
    if clawke_json.exists():
        try:
            data = json.loads(clawke_json.read_text())
            accounts = data.get("accounts", {})
            hermes_cfg = accounts.get("hermes", {})
            if hermes_cfg:
                config.ws_url = hermes_cfg.get("url", config.ws_url)
                config.gateway_id = hermes_cfg.get("gateway_id", config.gateway_id)
                config.account_id = hermes_cfg.get("account_id", config.account_id)
                if not config.gateway_id:
                    config.gateway_id = config.account_id
                config.model = hermes_cfg.get("model", config.model)
                config.provider = hermes_cfg.get("provider", config.provider)
                config.base_url = hermes_cfg.get("base_url", config.base_url)
                config.toolsets = hermes_cfg.get("toolsets", config.toolsets)
        except (json.JSONDecodeError, OSError) as e:
            print(f"[clawke-hermes] Warning: failed to parse {clawke_json}: {e}")

    # Environment variable overrides
    if os.environ.get("CLAWKE_WS_URL"):
        config.ws_url = os.environ["CLAWKE_WS_URL"]
    if os.environ.get("CLAWKE_ACCOUNT_ID"):
        config.account_id = os.environ["CLAWKE_ACCOUNT_ID"]
        if not config.gateway_id:
            config.gateway_id = config.account_id
    if os.environ.get("CLAWKE_GATEWAY_ID"):
        config.gateway_id = os.environ["CLAWKE_GATEWAY_ID"]
    if os.environ.get("CLAWKE_MODEL"):
        config.model = os.environ["CLAWKE_MODEL"]
    if os.environ.get("CLAWKE_PROVIDER"):
        config.provider = os.environ["CLAWKE_PROVIDER"]
    if os.environ.get("CLAWKE_BASE_URL"):
        config.base_url = os.environ["CLAWKE_BASE_URL"]

    return config
