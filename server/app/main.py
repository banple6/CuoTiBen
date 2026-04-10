"""
CuoTiBen PP-StructureV3 Gateway — FastAPI 入口
"""

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app import config
from app.routes.document_parse import router as parse_router

logging.basicConfig(
    level=getattr(logging, config.APP_LOG_LEVEL.upper(), logging.INFO),
    format="%(asctime)s  %(levelname)-7s  %(name)s  %(message)s",
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="CuoTiBen Document Parser",
    version="1.0.0",
    description="PP-StructureV3 安全网关 — 接收 iOS 上传、调用 AI Studio 云推理、归一化返回",
)

# CORS — 服务端对服务端调用通常不需要，预留给 Web 调试
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(parse_router)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "cuotiben-parser", "version": "1.0.0"}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app.main:app",
        host=config.APP_HOST,
        port=config.APP_PORT,
        log_level=config.APP_LOG_LEVEL,
        reload=False,
    )
