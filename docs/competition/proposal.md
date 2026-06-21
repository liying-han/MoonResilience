# MoonResilience 项目申报书

**项目名称：** MoonResilience：MoonBit 弹性治理基础库  
**参赛方向：** MoonBit 国产基础软件开源生态项目  
**开源许可证：** Apache-2.0  
**GitLink：** https://www.gitlink.org.cn/q2weasd/MoonResilience  
**GitHub：** https://github.com/liying-han/MoonResilience

## 一、项目目标与适用对象

MoonResilience 面向使用 MoonBit 开发服务端程序、任务执行器、消息消费者和基础工具的开发者。项目解决的不是某一种网络协议问题，而是调用链中反复出现的失败重试、故障隔离、流量控制和状态观察问题。核心库不绑定 HTTP 框架或系统时钟，调用方只需提供动作、策略状态和当前时间，便可在不同运行环境复用相同的治理逻辑。

## 二、项目方案与核心能力

项目提供四类基础策略并通过统一入口组合执行。Retry 支持固定、线性、指数和序列退避，可按最大次数、时间预算、错误码及可重试标记停止；Circuit Breaker 实现 Closed、Open、HalfOpen 状态机以及恢复探测限制；Rate Limiter 提供 token bucket 和 fixed window 两种算法；Bulkhead 管理并发槽位、有限等待队列、取消和 FIFO 晋升。统一执行链固定采用“限流、隔离、熔断、动作与重试”的顺序，返回最终状态、拒绝原因、尝试次数和执行轨迹。

## 三、技术路线

实现采用纯 MoonBit，不引入第三方依赖。策略对象均为显式状态值，函数返回更新后的新状态，不使用隐藏全局变量。重试、熔断和限流统一使用毫秒整数时间，测试与演示通过 VirtualClock 推进时间，不进行真实等待。配置模块负责 key=value 解析、默认值和字段约束；Telemetry 记录有界事件流、计数指标和延迟分桶，并可导出 Prometheus 文本；Diagnostics 检查策略健康状态与运行时不变量；Simulation 使用预设响应复现短暂故障、持续故障和恢复过程。

## 四、当前成果与验证方式

仓库已完成可运行核心库、CLI 示例、配置样例、API 与架构文档。当前约有 5.0k 行有效 MoonBit 代码和 100 项测试，覆盖退避边界、熔断状态转换、两类限流器、Bulkhead 容量耗尽、策略顺序、配置错误、时间模拟、指标导出及批量场景。评审者可运行 `moon check`、`moon test` 和 `moon run cmd/main` 验证；README 同时说明已知边界，避免将同步执行入口描述为完整异步调度系统。

## 五、公开开发与后续计划

GitLink 与 GitHub 保存相同版本，提交按模块、测试、文档和发布材料拆分，便于查看开发过程。后续工作将通过公开工单和功能分支记录，优先完成 HTTP 调用适配、等待队列超时、滑动窗口限流、事件订阅和跨后端一致性验证。阶段交付以测试可运行、接口文档同步和变更记录完整为验收条件。
