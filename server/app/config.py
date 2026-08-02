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
MATH_MAX_IMAGE_WIDTH: int = int(os.environ.get("MATH_MAX_IMAGE_WIDTH", "12000"))
MATH_MAX_IMAGE_HEIGHT: int = int(os.environ.get("MATH_MAX_IMAGE_HEIGHT", "12000"))
MATH_MAX_IMAGE_PIXELS: int = int(os.environ.get("MATH_MAX_IMAGE_PIXELS", "25000000"))
APP_ENV: str = os.environ.get("APP_ENV", "production").strip().lower()
MATH_ALLOW_DEV_USER_HEADER: bool = (
    APP_ENV in {"development", "test"}
    and os.environ.get("MATH_ALLOW_DEV_USER_HEADER", "false").strip().lower() == "true"
)

# ── 数学错题页（独立于英语资料解析链路） ──
MATH_WORKBOOK_STORAGE_ROOT: str = os.environ.get(
    "MATH_WORKBOOK_STORAGE_ROOT",
    ".data/math_workbook",
)
MATH_WORKBOOK_DB_PATH: str = os.environ.get(
    "MATH_WORKBOOK_DB_PATH",
    f"{MATH_WORKBOOK_STORAGE_ROOT}/math_workbook.sqlite3",
)
MATH_EXPLANATION_PROVIDER: str = os.environ.get("MATH_EXPLANATION_PROVIDER", "mock").strip().lower()
MATH_EXPLANATION_BASE_URL: str = os.environ.get("MATH_EXPLANATION_BASE_URL", "https://api.deepseek.com")
MATH_EXPLANATION_API_KEY: str = os.environ.get("MATH_EXPLANATION_API_KEY", os.environ.get("DEEPSEEK_API_KEY", ""))
MATH_EXPLANATION_MODEL: str = os.environ.get("MATH_EXPLANATION_MODEL", "deepseek-chat")
MATH_EXPLANATION_MODEL_VERSION: str = os.environ.get("MATH_EXPLANATION_MODEL_VERSION", "configured")
MATH_EXPLANATION_TEMPERATURE: float = float(os.environ.get("MATH_EXPLANATION_TEMPERATURE", "0.1"))
MATH_EXPLANATION_MAX_TOKENS: int = int(os.environ.get("MATH_EXPLANATION_MAX_TOKENS", "1200"))
MATH_EXPLANATION_MAX_RETRIES: int = int(os.environ.get("MATH_EXPLANATION_MAX_RETRIES", "2"))
MATH_EXPLANATION_TOTAL_TIMEOUT: float = float(os.environ.get("MATH_EXPLANATION_TOTAL_TIMEOUT", "30"))
MATH_EXPLANATION_CONNECT_TIMEOUT: float = float(os.environ.get("MATH_EXPLANATION_CONNECT_TIMEOUT", "5"))
MATH_EXPLANATION_READ_TIMEOUT: float = float(os.environ.get("MATH_EXPLANATION_READ_TIMEOUT", "25"))
MATH_EXPLANATION_WRITE_TIMEOUT: float = float(os.environ.get("MATH_EXPLANATION_WRITE_TIMEOUT", "5"))
MATH_EXPLANATION_MAX_RESPONSE_BYTES: int = int(os.environ.get("MATH_EXPLANATION_MAX_RESPONSE_BYTES", str(64 * 1024)))
MATH_EXPLANATION_PRICING_VERSION: str = os.environ.get("MATH_EXPLANATION_PRICING_VERSION", "2026-08")

def _optional_price(name: str) -> float | None:
    raw = os.environ.get(name, "").strip()
    return float(raw) if raw else None

MATH_EXPLANATION_INPUT_PRICE_PER_MILLION: float | None = _optional_price("MATH_EXPLANATION_INPUT_PRICE_PER_MILLION")
MATH_EXPLANATION_OUTPUT_PRICE_PER_MILLION: float | None = _optional_price("MATH_EXPLANATION_OUTPUT_PRICE_PER_MILLION")
MATH_EXPLANATION_LIVE_TEST: bool = os.environ.get("MATH_EXPLANATION_LIVE_TEST", "0") == "1"
