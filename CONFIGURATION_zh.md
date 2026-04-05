[English](CONFIGURATION.md)

# 高级配置与开发

本文档介绍服务端配置、Mock 离线开发模式和测试。

## 配置

服务端配置存储在 `~/.clawke/clawke.json`，首次运行时自动从模板创建。

```json
{
  "server": {
    "mode": "openclaw",
    "clientPort": 8765,
    "upstreamPort": 8766,
    "mediaPort": 8781,
    "fastMode": false,
    "logLevel": "info"
  },
  "openclaw": {
    "sharedFs": false,
    "mediaBaseUrl": "http://127.0.0.1:8781"
  },
  "relay": {
    "enable": true,
    "serverAddr": "relay.clawke.ai",
    "serverPort": 7000
  }
}
```

| 字段 | 说明 | 默认值 |
|------|------|--------|
| `server.mode` | `openclaw`（生产）或 `mock`（离线开发） | `openclaw` |
| `server.clientPort` | Flutter 客户端 WebSocket 端口 | `8765` |
| `server.upstreamPort` | OpenClaw Gateway WebSocket 端口 | `8766` |
| `server.mediaPort` | 媒体文件 HTTP 服务端口 | `8781` |
| `server.fastMode` | 跳过思考块，加速响应 | `false` |
| `server.logLevel` | 日志级别：`debug`, `info`, `warn`, `error` | `info` |
| `openclaw.sharedFs` | 服务端与 OpenClaw 是否共享文件系统 | `false` |
| `openclaw.mediaBaseUrl` | 媒体文件访问基础 URL | `http://127.0.0.1:8781` |
| `relay.enable` | 启用内置 Relay 隧道 | `true` |
| `relay.serverAddr` | Relay 服务器地址 | `relay.clawke.ai` |
| `relay.serverPort` | Relay 服务器端口 | `7000` |

### 环境变量

| 变量 | 说明 |
|------|------|
| `MODE` | 覆盖服务模式（`mock` 用于离线开发） |
| `CLAWKE_DATA_DIR` | 覆盖数据目录（默认：`~/.clawke/`） |

## Mock 模式

无需 AI 提供商即可运行服务端，适用于客户端 UI 开发和调试。

```bash
cd server
MODE=mock npm start
```

Mock 模式模拟：
- AI 流式文本响应
- 思考块（Thinking Block）
- 工具调用（Tool Call）
- 文件上传处理

## 测试

```bash
cd server
npm test                 # 运行全部 42 个测试用例
```

测试覆盖：
- CUP v2 协议编解码
- 认证中间件
- 媒体上传与解析
- TypeScript 集成验证

## iOS / macOS 构建

1. 复制 `client/ios/ExportOptions.plist.example` 为 `client/ios/ExportOptions.plist`
2. 将 `YOUR_TEAM_ID` 替换为你的 Apple Developer Team ID
3. Android 端，复制 `client/android/key.properties.example` 为 `client/android/key.properties`

## 数据目录

所有运行时数据存储在 `~/.clawke/`（可通过 `CLAWKE_DATA_DIR` 覆盖）：

```
~/.clawke/
├── clawke.json            # 用户配置
├── data/clawke.db         # SQLite 数据库
├── uploads/               # 用户上传文件
├── bin/                   # frpc 二进制（首次启动自动下载）
├── frpc.toml              # 自动生成的 Relay 配置
└── frpc.pid               # frpc 进程 PID
```
