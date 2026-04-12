"""
应用配置 — 所有敏感值从环境变量读取，不落盘
"""

import os
from dotenv import load_dotenv

load_dotenv()  # 本地开发时读取 .env，生产环境靠 systemd EnvironmentFile


def _require_env(key: str) -> str:
    val = os.environ.get(key)
    if not val:
        raise RuntimeError(f"缺少必需的环境变量: {key}")
    return val


# ── 版本信息 ──
PARSER_VERSION: str = "2026.04.11-1"
NORMALIZER_VERSION: str = "2026.04.11-wide-extractor"
SCHEMA_VERSION: str = "v2"

# ── AI Studio ──
AI_STUDIO_API_URL: str = _require_env("AI_STUDIO_API_URL")
AI_STUDIO_ACCESS_TOKEN: str = _require_env("AI_STUDIO_ACCESS_TOKEN")
AI_STUDIO_TIMEOUT: int = int(os.environ.get("AI_STUDIO_TIMEOUT", "60"))
AI_STUDIO_USE_DOC_ORIENTATION_CLASSIFY: bool = os.environ.get("AI_STUDIO_USE_DOC_ORIENTATION_CLASSIFY", "false").lower() == "true"
AI_STUDIO_USE_DOC_UNWARPING: bool = os.environ.get("AI_STUDIO_USE_DOC_UNWARPING", "false").lower() == "true"
AI_STUDIO_USE_TEXTLINE_ORIENTATION: bool = os.environ.get("AI_STUDIO_USE_TEXTLINE_ORIENTATION", "false").lower() == "true"
AI_STUDIO_USE_CHART_RECOGNITION: bool = os.environ.get("AI_STUDIO_USE_CHART_RECOGNITION", "false").lower() == "true"

# ── 服务 ──
APP_HOST: str = os.environ.get("APP_HOST", "0.0.0.0")
APP_PORT: int = int(os.environ.get("APP_PORT", "8900"))
APP_LOG_LEVEL: str = os.environ.get("APP_LOG_LEVEL", "info")
MAX_UPLOAD_SIZE: int = int(os.environ.get("MAX_UPLOAD_SIZE", str(20 * 1024 * 1024)))
