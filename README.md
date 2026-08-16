# MoonResilience

MoonResilience 是一个使用 MoonBit 编写的弹性治理基础库，用于服务调用、后台任务、消息消费和基础工具中的故障隔离与恢复。项目不绑定 HTTP 框架和系统时钟，调用方可以按需要接入现有应用。

## 功能范围

- **Retry**：固定、线性、指数、序列退避；支持最大次数、时间预算、错误码过滤和不可重试错误。
- **Circuit Breaker**：Closed、Open、HalfOpen 状态机；支持恢复窗口、探测并发限制、成功阈值和状态快照。
- **Rate Limiter**：token bucket 与 fixed window；返回剩余配额、拒绝原因和建议重试时间。
- **Bulkhead**：并发槽位、有限等待队列、FIFO 晋升、取消和容量快照。
- **Policy Chain**：按照限流、隔离、熔断、重试的固定顺序执行，并保留可检查的执行轨迹。
- **Telemetry**：有界事件日志、计数指标、延迟分桶和 Prometheus 文本导出。
- **Config**：`key=value` 配置解析、默认值、字段校验和错误行定位。
- **Simulation**：显式时间和预设故障响应，不进行真实等待即可验证策略行为。

当前版本包含约 4.8k 行有效 MoonBit 代码和 110 项测试。核心包没有第三方依赖。

## 仓库

- GitLink：<https://www.gitlink.org.cn/q2weasd/MoonResilience>
- GitHub：<https://github.com/liying-han/MoonResilience>

两个仓库同步发布，默认分支为 `master`。

## 快速开始

环境要求：已安装当前稳定版 MoonBit 工具链。

```bash
moon check
moon test
moon run cmd/main
```

CLI 会运行一个“上游连续两次超时、第三次恢复”的确定性场景，并输出尝试次数、虚拟时间线和指标摘要。

## 基本用法

```moonbit
let chain = @moonresilience.policy_chain(
  @moonresilience.retry_policy(
    4,
    5000,
    @moonresilience.exponential_backoff(100, 1000),
    ["timeout"],
  ),
  @moonresilience.new_circuit_breaker(
    @moonresilience.circuit_breaker_config(4, 1, 2000, 1),
  ),
  TokenBucketPolicy(
    @moonresilience.new_token_bucket(
      @moonresilience.token_bucket_config(20, 20, 1000),
      0,
    ),
  ),
  @moonresilience.new_bulkhead(
    @moonresilience.bulkhead_config(4, 8),
  ),
)

let result = @moonresilience.execute_with(
  chain,
  @moonresilience.execution_context(0, "inventory.query"),
  fn(attempt, _now_ms) {
    if attempt < 3 {
      Failure(@moonresilience.retryable_failure("timeout", "upstream timeout"))
    } else {
      Success("ok")
    }
  },
)
```

配置方式参见 [`examples/resilience.conf`](examples/resilience.conf)，完整接口说明参见 [`docs/API.md`](docs/API.md)。接入网络客户端前请阅读 [`docs/HTTP_ADAPTER.md`](docs/HTTP_ADAPTER.md) 中的错误分类和状态保存说明。

## 执行顺序

`execute_with` 使用固定顺序，便于预测资源消耗和拒绝原因：

1. 限流器申请一个许可；
2. Bulkhead 申请执行槽位；
3. 熔断器判断调用是否允许；
4. 执行动作，失败时由 RetryPolicy 判断是否重试；
5. 更新熔断器并释放 Bulkhead 槽位。

同步执行入口不会等待 Bulkhead 队列。进入等待队列时会返回 `RejectedByBulkhead`，调用方可使用独立调度器处理排队请求。

## 配置

```text
retry.max_attempts=4
retry.max_elapsed_ms=5000
retry.backoff=exponential
retry.base_delay_ms=100
retry.max_delay_ms=1000
breaker.failure_threshold=4
breaker.success_threshold=1
breaker.open_window_ms=2000
limiter.kind=token_bucket
limiter.capacity=20
limiter.refill_tokens=20
limiter.window_ms=1000
bulkhead.max_concurrent=4
bulkhead.max_waiting=8
```

`parse_config` 会忽略空行和以 `#` 开头的注释。未知字段、非整数值和约束冲突会返回带行号的 `ConfigError`。

## 项目结构

```text
.
├── retry.mbt                 # 重试与退避
├── circuit_breaker.mbt       # 熔断器状态机
├── rate_limiter.mbt          # 两类限流器
├── bulkhead.mbt              # 并发隔离与等待队列
├── policy_chain.mbt          # 统一执行入口
├── telemetry.mbt             # 事件与计数指标
├── latency.mbt               # 延迟分桶
├── metrics_export.mbt        # Prometheus 文本导出
├── config.mbt                # 配置解析与校验
├── simulation.mbt            # 确定性故障模拟
├── diagnostics.mbt           # 健康状态与不变量检查
├── registry.mbt              # 命名策略目录
├── batch.mbt                 # 批量场景执行
├── cmd/main                  # 可运行示例
└── docs                      # API、架构与比赛材料
```

## 开发与验证

```bash
moon info
moon fmt
moon check --warn-list +73
moon test
moon build --target all
moon run cmd/main
moon coverage analyze
```

提交代码前请阅读 [`CONTRIBUTING.md`](CONTRIBUTING.md)。版本变化记录在 [`CHANGELOG.md`](CHANGELOG.md)，后续工作记录在 [`ROADMAP.md`](ROADMAP.md)。

## 当前边界

- 项目提供与框架无关的策略内核，不直接发起网络请求。
- 时间由调用方显式传入；生产接入层需要提供实际时钟。
- 当前执行入口为同步模型，等待队列只维护调度状态。
- 配置解析器面向小型本地配置，不替代通用配置文件格式。

## 许可证

Apache-2.0，详见 [`LICENSE`](LICENSE)。
