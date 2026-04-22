# AI Core 服务器部署 Gate Runbook

## 目标服务器

`47.94.227.58`

## 部署前置

- 必须能 SSH 登录
- 必须知道运行方式：`systemd / pm2 / docker / node`
- 必须备份当前版本
- 必须配置 `.env`
- 必须能重启服务

如果 SSH 不可用：

- 停止
- 记录“线上部署受 SSH 权限阻塞”
- 不得继续
- 不得声称部署成功

## SSH Gate

```bash
ssh root@47.94.227.58
```

如果成功，按顺序执行：

1. 找部署目录
2. 备份
3. 上传
4. 安装依赖
5. 配置 `.env`
6. 重启服务
7. `curl /health`
8. `curl /ai/explain-sentence`
9. `curl /ai/analyze-passage`
10. 记录 `request_id`

## 建议的线上核对流程

```bash
ssh root@47.94.227.58
pwd
ls
```

确认部署目录后：

```bash
cp -R <deploy-dir> <deploy-dir>.backup-$(date +%Y%m%d-%H%M%S)
```

上传新版本后，按真实运行方式执行：

- `systemd`：`systemctl restart <service-name>`
- `pm2`：`pm2 restart <app-name>`
- `docker`：`docker compose up -d --build`
- `node`：按现网约定重启进程

## 线上验证

```bash
curl http://127.0.0.1:<port>/health
curl -X POST http://127.0.0.1:<port>/ai/explain-sentence -H 'Content-Type: application/json' -d '<payload>'
curl -X POST http://127.0.0.1:<port>/ai/analyze-passage -H 'Content-Type: application/json' -d '<payload>'
```

验收必须满足：

- 服务成功重启
- `/health` 返回 `ai_gateway`
- 两条 AI 路由都拿到结构化响应
- 记录了线上 `request_id`

## SSH 失败时的唯一结论

本地验证通过，线上部署受 SSH 权限阻塞。
