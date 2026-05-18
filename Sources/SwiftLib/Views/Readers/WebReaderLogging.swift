import OSLog


/// 在线阅读流水线日志：在「控制台」App 中过滤子系统 `SwiftLib`、类别 `OnlineReadable`；用于核对「并未调用浏览器里的 reader.js / Reader.apply」。
let onlineReadableLog = Logger(subsystem: "SwiftLib", category: "OnlineReadable")

