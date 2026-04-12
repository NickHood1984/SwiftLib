# Changelog

## Unreleased

## v1.1.1 — 2026-04-13

### 修复

- 修复 CLI 工具安装到 /usr/local/bin 时因权限不足直接失败的问题；现在会在需要时自动弹出 macOS 管理员密码窗口完成安装。
- 修复 CLI 工具卸载在提权安装后可能无法删除的问题；现在会在需要时同样请求管理员授权。

### 兼容性

- 补齐缺失的 onboarding 兼容层，恢复当前工作区的可编译状态，避免热修复版本被无关残留代码阻塞。

## v1.1.0 — 2026-04-12

### 新增

- 增加 WPS Office 插件安装器、资源打包与任务窗格支持。
- 增加 Sparkle 自动更新接入、appcast 生成脚本和 GitHub Pages 发布流程。
- 增加阅读器操作条自适应布局与对应测试。

### 改进

- 重做 PDF / 网页阅读器的悬浮操作条布局与窗口默认尺寸。
- 优化标注侧边栏和网页标注卡片的悬停交互、完整笔记预览与滚动稳定性。
- 引用渲染支持按需跳过 bibliography，并降低 JSContext 池上限以控制内存。

### 清理

- 移除尚未定稿的新手引导实现。
- 删除旧的阅读器实现说明文档和 `PROMO.md`。

### WPS 插件（macOS 任务窗格）

#### 修复

- **任务窗格冻结**：将引文样式下拉菜单从原生 `<select>` 替换为自定义 HTML 菜单（button + listbox），绕过 WPS macOS 宿主对原生下拉的处理导致 WebView 冻结的问题。原生 `<select>` 保留为隐藏的状态存储，不再渲染。

- **插入引文后上角标溢出**：在 `refreshAllCitations` 最终块中新增 `WPSDocument.resetCaretSuperscript()`，通过 COM 接口强制将光标处的 `Font.Superscript` 置为 `false`；完成后通过系统事件触发一次隐式焦点往返（`System Events` → WPS），使 WPS 重新从光标处读取字符格式，从而保证插入引文后直接输入的文字为正文格式而非上角标。

- **插入引文后焦点跳回搜索框**：移除 `requestSearchFocus()`（原在插入成功后经 80ms 定时器将焦点移至任务窗格搜索输入框）。COM 书签写入操作本身在 WPS 进程内执行，光标自然停留在文档中，无需额外焦点操作。

- **样式切换空操作防抖**：`onStyleChange()` 增加提前返回判断——若新样式与当前样式相同，则跳过所有刷新与焦点操作。

#### 新增

- `WPSDocument.resetCaretSuperscript()`：对折叠光标处显式清除上下标格式，防止后续输入继承引文的上角标样式。

- `triggerFocusBounce()`：通用焦点往返辅助函数（取代原仅供样式切换使用的 `triggerFocusBounceForStyleSwitch()`），目前仅在插入引文成功后调用。

#### 清理

- 移除 `requestSearchFocus()` 函数及其所有调用点。

---

### 服务器（`WordAddinServer.swift`）

#### 新增

- **`POST /api/wps/focus-bounce`**：焦点往返接口。通过 `osascript` 内联脚本短暂激活 macOS `System Events`（后台守护进程，无可见界面），再立即重新激活 WPS，触发 WPS 文档区域重新获得焦点并刷新光标字符格式。

- **`POST /api/perf-log`**：接收 WPS 插件端发送的性能日志行，打印到服务器标准输出，便于开发调试。

- **`/wps/*` 静态文件路由**：`/wps/foo.js` 映射到 `Resources/WPSAddin/foo.js`，支持 WPS 插件资源的独立路径空间。

- **`focusBounceQueue`**：专用 `DispatchQueue`，隔离焦点往返的 `osascript` 进程调用，避免阻塞主服务器队列。

#### 改进

- **`POST /api/render-document`**：新增 `includeBibliography` 参数（默认 `true`），允许调用方跳过参考文献渲染，减少仅需刷新引文时的计算量。

- **`POST /api/render-document`**：当 `citations` 为空时提前返回空响应，避免无意义的引擎调用。

- `Bundle` 扩展改为 `internal`（去掉 `private`），供测试目标访问。

---

## v1.0.0 — 2026-03-xx

初始开源发布。
