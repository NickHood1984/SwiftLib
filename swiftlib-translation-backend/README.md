# SwiftLib Translation Backend

独立的中文元数据后端，作为 SwiftLib 主程序的本地伴生服务运行。

## 目标

- 使用 `translation-server` 作为 translator runtime
- 叠加 `translators_CN` 作为中文 translator 覆盖层
- 对 SwiftLib 暴露稳定的本地 HTTP API，而不是直接暴露 raw translation-server 端点

## 当前实现

- 启动后监听 `127.0.0.1` 随机端口
- 通过 stdout 输出握手 JSON：`{port, token, version, capabilities}`
- 支持：
  - `GET /health`
  - `GET /capabilities`
  - `POST /resolve`
  - `POST /resolve-selection`
  - `POST /refresh`
  - `POST /maintenance/update-translators`

## 运行方式

```bash
cd swiftlib-translation-backend
TRANSLATION_SERVER_URL=http://127.0.0.1:1969 npm start
```

默认会代理到 `http://127.0.0.1:1969` 的 `translation-server`。

## translators 更新

当前仓库提供：

- `scripts/update-translators.mjs`
- `scripts/build-overlay.mjs`

用于维护 `translation-server` 与 `translators_CN` 的 overlay 目录。脚本会优先读取：

- `vendor/translation-server`
- `vendor/translators_CN`

如果这两个上游目录不存在，更新命令会返回当前状态而不修改任何内容。
