# HTTP 适配指南

MoonResilience 不直接依赖 HTTP 客户端。适配层负责执行请求、读取单调时间，并将客户端结果转换为 `ActionOutcome`。

## 错误分类

建议按以下规则建立第一版映射，具体业务可通过错误码过滤覆盖：

| HTTP 结果 | `AttemptFailure` | 默认建议 |
|---|---|---|
| 连接失败、连接重置 | `retryable=true` | 允许重试 |
| 读取超时 | `retryable=true` | 允许重试，并受总时间预算限制 |
| 主动取消 | `retryable=false` | 立即停止 |
| 408、425、429 | `retryable=true` | 允许重试；适配器可读取服务端重试时间 |
| 400、401、403、404、409、422 | `retryable=false` | 立即返回业务失败 |
| 500、502、503、504 | `retryable=true` | 允许重试 |
| 其他响应 | 由业务规则决定 | 默认不重试 |

不要只根据“4xx”或“5xx”整体分类。429 与 503 常用于临时过载，而 401、403 通常需要修改凭据或权限，重复调用不会自行恢复。

## 适配边界

```moonbit
let context = @moonresilience.execution_context(monotonic_now_ms(), "user.fetch")
let result = @moonresilience.execute_with(chain, context, fn(
  _attempt,
  _policy_time_ms,
) {
  match http_get("https://service.example/users/42") {
    HttpOk(body) => Success(body)
    HttpTimeout =>
      Failure(@moonresilience.retryable_failure("http_timeout", "read timeout"))
    HttpStatus(503) =>
      Failure(@moonresilience.retryable_failure("http_503", "unavailable"))
    HttpStatus(status) =>
      Failure(
        @moonresilience.permanent_failure(
          "http_" + status.to_string(),
          "request rejected",
        ),
      )
  }
})
```

上例中的 `http_get` 是接入层函数，不属于核心包。实际项目应在独立 MoonBit 包中引入具体 HTTP 客户端。

## 时间与超时

- `ExecutionContext.now_ms` 应来自单调时钟，而不是可校准的墙上时间。
- HTTP 客户端的单次请求超时应小于重试总时间预算。
- 当前核心执行入口计算退避时间，但不负责真实 sleep；生产适配器应按执行轨迹或调度接口等待。
- 收到服务端 `Retry-After` 时，可将它转换为下一次调度时间，但仍不得突破 `max_elapsed_ms`。

## 状态保存

执行结束后保存 `ExecutionResult.chain`，下一次请求继续使用该状态。若每次请求都重新创建 `PolicyChain`，熔断器、限流配额和指标将无法跨调用生效。

## 观察与诊断

适配器可以把 `ExecutionResult.trace` 转为 `EventLog`，再生成 `MetricsSnapshot`。需要 Prometheus 文本时使用 `export_prometheus`。排查问题时同时记录 operation、错误码、尝试次数和 `BreakerSnapshot`，不要记录令牌、Cookie 或完整请求体。

完整公共接口见 [`API.md`](API.md)，策略顺序见 [`ARCHITECTURE.md`](ARCHITECTURE.md)。
