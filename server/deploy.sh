#!/usr/bin/env bash
# ───────────────────────────────────────────────────────────
# CuoTiBen PP-StructureV3 Gateway — 服务器部署脚本
# 用法:
#   1) 在本地填好 server/.env（复制 .env.example 改名）
#   2) 执行:  bash deploy.sh  <server_ip>  <ssh_user>
# ───────────────────────────────────────────────────────────
set -euo pipefail

SERVER="${1:?用法: bash deploy.sh <server_ip> [ssh_user]}"
USER="${2:-root}"
REMOTE_DIR="/opt/cuotiben-parser"

echo "======= 部署到 ${USER}@${SERVER}:${REMOTE_DIR} ======="

# 1) 上传代码
echo ">>> 上传文件..."
ssh "${USER}@${SERVER}" "mkdir -p ${REMOTE_DIR}"
rsync -avz --exclude '.venv' --exclude '__pycache__' --exclude '.env' \
    ./ "${USER}@${SERVER}:${REMOTE_DIR}/"

# 2) 上传 .env（如果本地存在）
if [[ -f .env ]]; then
    echo ">>> 上传 .env..."
    scp .env "${USER}@${SERVER}:${REMOTE_DIR}/.env"
fi

# 3) 远程安装依赖 + 部署 systemd
ssh "${USER}@${SERVER}" bash -s <<'REMOTE_SCRIPT'
set -euo pipefail
cd /opt/cuotiben-parser

# Python venv
if [[ ! -d .venv ]]; then
    python3 -m venv .venv
fi
.venv/bin/pip install --upgrade pip
.venv/bin/pip install -r requirements.txt

# systemd
cp deploy/cuotiben-parser.service /etc/systemd/system/cuotiben-parser.service
systemctl daemon-reload
systemctl enable cuotiben-parser
systemctl restart cuotiben-parser

echo ">>> 服务状态:"
systemctl status cuotiben-parser --no-pager || true

echo ""
echo ">>> 健康检查:"
sleep 2
curl -sf http://127.0.0.1:8900/health || echo "（服务可能还在启动中，请稍后重试）"
REMOTE_SCRIPT

echo ""
echo "======= 部署完成 ======="
echo "  健康检查: curl http://${SERVER}:8900/health"
echo "  查看日志: ssh ${USER}@${SERVER} journalctl -u cuotiben-parser -f"
echo ""
echo "  测试解析:"
echo "    curl -X POST http://${SERVER}:8900/api/document/parse \\"
echo "      -F 'file=@test.pdf' \\"
echo "      -F 'document_id=test-001' \\"
echo "      -F 'title=测试文档' \\"
echo "      -F 'file_type=PDF'"
