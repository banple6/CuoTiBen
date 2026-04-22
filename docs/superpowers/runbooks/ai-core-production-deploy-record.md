# AI Core 生产部署记录

## 概览

- 部署日期：`2026-04-22`
- 部署时间窗口：`2026-04-22 18:21:08 CST` 至 `2026-04-22 18:22:35 CST`
- 部署来源分支：`codex/ai-core-rebuild`
- 后端部署基线提交：`69f77fb`

## 生产目标

- Server：`47.94.227.58`
- Service：`cuotiben-backend.service`
- systemd unit：`/etc/systemd/system/cuotiben-backend.service`
- Deploy path：`/root/CuoTiBen/backend`
- Backup path：`/www/backup/backend-20260422-182108`

## 部署动作

1. 通过 SSH key 登录 `root@47.94.227.58`
2. 识别现网运行方式为 `systemd`
3. 备份旧后端目录到 `/www/backup/backend-20260422-182108`
4. 将当前分支 `backend/` 同步到 `/root/CuoTiBen/backend`
5. 按新 AI gateway 配置重写服务器 `.env`
6. 执行 `npm install --omit=dev`
7. 执行 `find src -name "*.js" -print0 | xargs -0 -n1 node --check`
8. 重启 `cuotiben-backend.service`

## 生产环境变量

仅记录变量名，不记录真实值：

- `PORT`
- `NOVAI_API_KEY`
- `AI_PROVIDER`
- `AI_MODEL`
- `AI_BASE_URL`
- `AI_API_KIND`
- `AI_TIMEOUT_MS`
- `AI_MAX_RETRIES`
- `AI_CIRCUIT_BREAKER_ENABLED`

## 服务状态

- `systemctl is-active cuotiben-backend.service`：`active`
- `ActiveEnterTimestamp`：`Wed 2026-04-22 18:22:35 CST`
- 当前主进程：`/usr/bin/node /root/CuoTiBen/backend/server.js`

## 上游预检

部署前已用服务器现有密钥完成两条上游探测，均返回 `HTTP 200`：

- `https://us.novaiapi.com/v1/messages`
- `https://once.novai.su/v1/messages`

## 线上 smoke 结果

### 服务器本机 curl

访问目标：`http://127.0.0.1`

- `/health`
  - `ok=true`
  - `configured=true`
  - `provider=claude`
  - `model=claude-opus-4-6`
  - `api_kind=anthropic-messages`
  - `circuit_state=closed`
- `/ai/explain-sentence`
  - `success=true`
  - `used_fallback=false`
  - `request_id=186cfc82-2574-4204-9e0c-918a32f7b2db`
- `/ai/analyze-passage`
  - `success=true`
  - `used_fallback=false`
  - `request_id=048b5635-6ee6-47dd-9bae-6ff40390e9ee`

### 公网 curl

访问目标：`http://47.94.227.58`

- `/health`
  - `ok=true`
  - `configured=true`
  - `provider=claude`
  - `model=claude-opus-4-6`
  - `circuit_state=closed`
- `/ai/explain-sentence`
  - `success=true`
  - `used_fallback=false`
  - `request_id=d3cd2bc5-307c-45f6-87be-103bcbfd0285`
- `/ai/analyze-passage`
  - `success=true`
  - `used_fallback=false`
  - `request_id=8ecb5553-dc48-46b0-93a0-39315ca51c44`

## request_id 样本

- 服务器本机 explain：`186cfc82-2574-4204-9e0c-918a32f7b2db`
- 服务器本机 analyze：`048b5635-6ee6-47dd-9bae-6ff40390e9ee`
- 公网 explain：`d3cd2bc5-307c-45f6-87be-103bcbfd0285`
- 公网 analyze：`8ecb5553-dc48-46b0-93a0-39315ca51c44`

## 日志摘记

- `journalctl -u cuotiben-backend.service` 已记录：
  - 服务重启成功
  - `/health` 命中
  - explain / analyze 请求成功
  - 与上面的 `request_id` 一致

## 回滚路径

如需回滚，按这个顺序执行：

1. `systemctl stop cuotiben-backend.service`
2. 清理当前部署目录中的后端文件
3. 将 `/www/backup/backend-20260422-182108` 恢复到 `/root/CuoTiBen/backend`
4. 确认恢复后的 `.env` 与依赖目录一致
5. `systemctl restart cuotiben-backend.service`
6. 重新执行 `/health`、`/ai/explain-sentence`、`/ai/analyze-passage` smoke

## 结论

- 本次生产部署已完成
- 新 AI gateway 已在生产运行
- explain-sentence / analyze-passage 生产 smoke 已通过
- 本记录不包含任何真实密钥、Authorization 或服务器密码
