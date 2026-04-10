"""
文件类型辅助
"""


MIME_MAP = {
    "pdf": "application/pdf",
    "png": "image/png",
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "heic": "image/heic",
    "txt": "text/plain",
}


def guess_mime(filename: str) -> str:
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    return MIME_MAP.get(ext, "application/octet-stream")


def infer_file_type(filename: str, declared: str | None = None) -> str:
    """返回 'pdf' / 'image' / 'text'"""
    if declared and declared.lower() in ("pdf", "image", "text", "scan"):
        return declared.lower()
    ext = filename.rsplit(".", 1)[-1].lower() if "." in filename else ""
    if ext == "pdf":
        return "pdf"
    if ext in ("png", "jpg", "jpeg", "heic", "tiff", "bmp"):
        return "image"
    return "text"
