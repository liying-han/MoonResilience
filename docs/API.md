# API 说明

本文档对应 `0.2.0`。公开接口以 `moon info` 生成的 `moonresilience.mbti` 为准。

## Retry

- `fixed_backoff(delay_ms)`：固定退避。
- `linear_backoff(initial_delay_ms, step_ms, max_delay_ms)`：线性增长并封顶。
- `exponential_backoff(base_delay_ms, max_delay_ms)`：按二倍增长并封顶。
- `sequence_backoff(delays_ms)`：按数组顺序返回延迟，超出后使用最后一项。
- `retry_policy(max_attempts, max_elapsed_ms, backoff, retryable_codes)`：构造策略。
- `should_retry(policy, failure, attempt, elapsed_ms)`：判断当前失败是否继续重试。

`retryable_codes` 为空时接受全部 `retryable=true` 的失败；非空时还要求错误码在列表中。

## Circuit Breaker

`breaker_before_call` 返回 `BreakerAllowed` 或 `BreakerRejected`。半开探测获得许可后，调用方必须调用以下函数之一：

- `breaker_record_success`
- `breaker_record_failure`
- `breaker_cancel_call`

`breaker_snapshot` 返回当前状态、连续失败数、半开探测数、剩余打开时间和转换次数。

## Rate Limiter

Token bucket 适合允许短时突发的场景；fixed window 适合按固定时间窗口控制配额。两类 `acquire` 接口均返回新的状态和 `RateLimitDecision`。状态值不可变，调用方应保存返回的新实例。

## Bulkhead

`bulkhead_admit` 的结果：

- `BulkheadEntered`：获得执行槽位；
- `BulkheadQueued`：进入 FIFO 等待队列；
- `BulkheadRejected`：执行与等待容量均耗尽，或调用标识非法。

执行结束调用 `bulkhead_complete`。若队列非空，该函数会将第一项晋升为 active。

## Policy Chain

```moonbit
pub fn[T] execute_with(
  chain : PolicyChain,
  context : ExecutionContext,
  action : (Int, Int) -> ActionOutcome[T],
) -> ExecutionResult[T]
```

动作参数依次为尝试序号和当前显式时间。结果包含最终状态、尝试次数、起止时间和执行轨迹。策略状态不会使用全局变量，下一次调用需要传入上一次结果中的 `chain`。

## Telemetry

- `EventLog`：有界事件数组，超过容量时丢弃最早事件并增加 `dropped_events`。
- `Metrics`：计数器和延迟累计值。
- `LatencyHistogram`：用户指定桶边界，支持合并和 P50/P90/P99 近似值。
- `export_prometheus`：导出计数与延迟摘要。
- `export_latency_prometheus`：导出累计延迟桶。

Prometheus 导出器校验指标前缀和标签名，并转义标签值中的反斜线与双引号。

## Config

`parse_config` 返回 `Result[ResilienceConfig, ConfigError]`。成功后可调用 `config_to_policy_chain(config, now_ms)` 创建执行链。支持字段见 `examples/resilience.conf`。

## Simulation

`simulation_scenario` 接收一组 `SimulatedResponse`。`simulate` 按策略执行响应序列，生成 `SimulationResult`，其中包含结果、虚拟时间线、事件和指标。该模块只推进整数时间，不调用 sleep。

`run_batch` 用同一条策略链顺序运行多个场景，可选择遇到首个失败时停止。

## Diagnostics

`inspect_policy_chain` 汇总熔断器、限流器和 Bulkhead 状态，返回 `Healthy`、`Degraded` 或 `Unavailable`。`check_policy_invariants` 用于发现手工构造状态中的容量越界和重复调用标识。

## Registry

`PolicyRegistry` 管理命名策略，支持 add、replace、remove、find 和 default。它是内存数据结构，不负责持久化或并发同步。
