# PDFReaderView 实现说明

本文档描述 `PDFReaderView` 模块的核心架构，包括悬浮标注工具栏、标注渲染与同步，以及高亮点击跳转侧边栏三个功能的完整实现思路。

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `Views/PDFReaderView.swift` | 主视图、ViewModel、Coordinator、所有标注逻辑 |
| `Views/AnnotationSidebarView.swift` | 右侧标注卡片列表（`AnnotationCard`）|
| `Models/PDFAnnotationRecord.swift` | 持久化模型（GRDB）|
| `Helpers/PDFView+ElegantScrollers.swift` | PDFView 扩展：内部滚动视图查找 + 滚动条美化 |

---

## 一、悬浮标注工具栏

### 1.1 整体数据流

```
用户拖选文字
    │
    ▼
CommitAwarePDFView.mouseUp / keyUp
    │  commitSelectionIfNeeded()
    ▼
Coordinator.handleCommittedSelection(selection)
    │  计算 pageRects + PDF 锚点
    ▼
PDFReaderViewModel.stageSelection(...)
    │  存入 stagedSelectionPDFAnchor（页面坐标系）
    ▼
Coordinator.updateSelectionToolbarLayout()
    │  pdfView.convert(anchor, from: page)
    │  pdfView.visibleRect 做可见性判断
    │  换算为 SwiftUI overlay 坐标
    ▼
PDFReaderViewModel.selectionToolbarLayout（@Published）
    │
    ▼
PDFReaderView.selectionActionBarOverlay
    └─ SelectionActionBar.position(x:y:)  ← 工具栏显示在此
```

### 1.2 锚点存储：PDF 页面坐标系

```swift
struct StagedSelectionPDFAnchor: Equatable {
    var pageIndex: Int
    var lastLineBounds: CGRect   // PDF 页面坐标系，不随滚动/缩放变化
}
```

锚点取选区**最后一行**的边界矩形（`selection.selectionsByLine().last`），工具栏定位在该行底边正下方。使用页面坐标而非 viewport 坐标，是为了在滚动后能重新换算出正确位置。

### 1.3 滚动跟随：监听 boundsDidChange

`Coordinator.ensureObservers(for:)` 在两个时机监听更新：

| 通知 | 触发场景 |
|------|---------|
| `NSView.boundsDidChangeNotification`（clipView）| 用户滚动 PDF |
| `PDFViewScaleChanged` | 用户缩放 PDF |

每次触发时调用 `updateSelectionToolbarLayout()`，从 PDF 页面坐标实时换算 viewport 坐标，不存死坐标。

```swift
// ensureObservers 安装时机：
// 1. makeNSView 结束后 async（视图进入 hierarchy 后）
// 2. makeNSView 结束后 asyncAfter 0.1s（给 PDFKit 子视图 layout 的时间）
// 3. updateNSView 每次调用（重试兜底）
```

### 1.4 关键修复：internalScrollView

PDFKit 的内部滚动视图（私有类 `PDFScrollView`）是 `PDFView` 的**子视图**，而 `NSView.enclosingScrollView` 只向上查找祖先，因此永远返回 nil。

```swift
// PDFView+ElegantScrollers.swift
var internalScrollView: NSScrollView? {
    // 最快路径：PDFScrollView 就是第一个子视图
    subviews.first as? NSScrollView ?? descendantScrollViews(of: self).first
}
```

受影响的三处调用均已替换：

| 位置 | 用途 |
|------|------|
| `ensureObservers` | 拿到 `clipView` 安装滚动监听器 |
| `updateSelectionToolbarLayout` | 确认滚动视图可用 |
| `centerRectInViewport` | 侧边栏跳转时精确定位 |

### 1.5 关键修复：坐标系对齐

`scrollView.contentView.bounds` 是**文档坐标系**（含累积滚动偏移，y 值可达数万点），而 `pdfView.convert(rect, from: page)` 返回 **PDFView 自身坐标系**。两者不能直接用于 `intersects` 判断。

正确做法是用 `pdfView.visibleRect`，它与 `convert` 结果处于同一坐标系：

```swift
let rectInPDFView = pdfView.convert(anchor.lastLineBounds, from: page)
let visibleRect = pdfView.visibleRect   // 同一坐标系 ✓

if !rectInPDFView.intersects(visibleRect) {
    // 选区滚出视口，隐藏工具栏
}
```

坐标换算到 SwiftUI overlay（以 `visibleRect.origin` 为基准）：

```swift
let midX = rectInPDFView.midX - visibleRect.minX

if pdfView.isFlipped {
    lineTopSwift    = rectInPDFView.minY - visibleRect.minY
    lineBottomSwift = rectInPDFView.maxY - visibleRect.minY
} else {
    lineBottomSwift = visibleRect.height - (rectInPDFView.minY - visibleRect.minY)
    lineTopSwift    = visibleRect.height - (rectInPDFView.maxY - visibleRect.minY)
}
```

### 1.6 工具栏位置逻辑

- 默认放在选区**下方** 12pt 处
- 若下方空间不足（距底边 < 6pt），翻转到**上方**显示
- 横向超出边界时自动收拢到 margin 范围内

```swift
let belowY = lineBottomSwift + gap + barH / 2
let aboveY = lineTopSwift  - gap - barH / 2

if belowY + barH / 2 <= overlayH - margin {
    centerY = belowY
} else if aboveY - barH / 2 >= margin {
    centerY = aboveY
} else {
    centerY = belowY  // 两侧都放不下时的兜底
}
```

---

## 二、工具栏 UI（SelectionActionBar）

```
┌─────────────────────────────────┐
│  [高亮]  [下划线]  [笔记]  │ ●  │
└─────────────────────────────────┘
   3 个操作按钮      分隔线  颜色圆点
```

- **深色背景**，深色/浅色模式自适应（dark: `0.22`，light: `0.13`）
- **颜色圆点**：点击弹出 Popover，展示 6 色色板，不平铺
- **无选区文本预览**：用户已经看到自己选中了什么，预览冗余
- SwiftUI overlay + `.position(x:y:)` 定位，无需 `addSubview`
- `.transition(.scale.combined(with: .opacity))` 弹出/消失动画

---

## 三、标注持久化与渲染同步

### 3.1 持久化模型（PDFAnnotationRecord）

- 存储：GRDB，表名 `pdfAnnotation`
- 矩形以 JSON 数组（`rectsData`）存储，支持跨行高亮的多段矩形
- `unionBounds` 作为 `PDFAnnotation.bounds`，`quadrilateralPoints` 精确描述各段

### 3.2 增量同步（syncAnnotations）

```
数据库 annotations 数组
    │
    ├─ 已删除的 key → removeAnnotation from PDFPage
    │
    └─ 新增/变更的 record（renderHash 不同）
           → createPDFAnnotation(from:)
           → page.addAnnotation(annotation)
           → 存入 trackedAnnotations[id]
```

`renderHash` 由 `id + type + color + pageIndex + noteText + rects` 组成，避免无变化时重复渲染。

### 3.3 TrackedAnnotation

```swift
struct TrackedAnnotation {
    let annotation: PDFAnnotation   // PDFKit 渲染对象（弱引用语义由 page 持有）
    let pageIndex: Int
    let renderHash: Int
}

var trackedAnnotations: [Int64: TrackedAnnotation] = [:]
// key = PDFAnnotationRecord.id
```

---

## 四、高亮点击 → 侧边栏卡片跳转

```
用户单击已有高亮
    │
    ▼
CommitAwarePDFView.mouseUp
    │  currentSelection 为空（非拖选）
    │  annotationAtClick(event)
    │    convert(locationInWindow, from: nil) → PDFView 坐标
    │    convert(point, to: page)             → PDF 页面坐标
    │    page.annotation(at: pdfPoint)        → PDFAnnotation?
    ▼
Coordinator.handleAnnotationClicked(annotation)
    │  遍历 trackedAnnotations
    │  找到 tracked.annotation === annotation 的 key
    │  viewModel.selectedAnnotationId = key
    ▼
AnnotationSidebarView
    └─ .onChange(of: selectedAnnotationId)
         proxy.scrollTo(newId, anchor: .center)   ← 自动滚动 + 高亮卡片
```

点击顺序判断：`mouseUp` 优先处理文字选中（有 `currentSelection`），无选中时再判断是否命中 annotation，最后才触发清空选区。

---

## 五、关键参数

| 参数 | 值 | 说明 |
|------|-----|------|
| `barW` | 180 pt | 工具栏估算宽度（用于边界保护） |
| `barH` | 50 pt | 工具栏估算高度 |
| `gap` | 12 pt | 选区底边到工具栏中心的间距 |
| `margin` | 6 pt | 工具栏距视口边缘的最小安全距离 |
| flash 高亮持续 | 0.35 s | 侧边栏跳转后蓝色闪烁提示时长 |
| ensureObservers 延迟 | 0.1 s | 等待 PDFKit 子视图完成 layout |
