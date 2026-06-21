# 架构说明

## 设计目标

MoonResilience 将策略计算与网络、线程、系统时钟分离。核心函数接收状态和显式时间，返回新状态和决策，因此同一套逻辑可以用于服务器、任务执行器、命令行工具和离线测试。

## 模块关系

```text
Config ----> PolicyChain <---- Registry
                |
        +-------+-------+
        |       |       |
     Limiter Bulkhead Breaker ---- Retry
        |       |       |           |
        +-------+-------+-----------+
                |
          ExecutionTrace
                |
      Telemetry / Diagnostics
                |
    Prometheus / Simulation / CLI
```

## 状态所有权

所有策略类型均为显式值。接口不会将策略保存到全局变量：

1. 调用方持有 `PolicyChain`；
2. `execute_with` 使用当前状态执行；
3. `ExecutionResult.chain` 返回更新后的状态；
4. 调用方将它传给下一次执行。

这种方式避免隐藏共享状态，也让单元测试能够从任意状态开始。

## 策略顺序

限流放在最外层，防止被拒绝请求占用隔离资源；Bulkhead 随后限制并发；熔断器在每次尝试前检查；重试只包裹实际动作。失败结束时统一释放 Bulkhead 槽位。

## 时间模型

重试、熔断、限流和模拟均使用毫秒整数。核心库不读取系统时间。生产适配器应在请求进入时提供单调时间；测试可使用 `VirtualClock`。墙上时间回拨不会影响已经构造的状态，但调用方仍应优先提供单调时钟。

## 错误模型

动作失败使用 `AttemptFailure`，策略拒绝和重试耗尽使用 `ExecuteError`。配置、注册表分别使用 `ConfigError`、`RegistryError`。错误格式化函数只用于日志和 CLI，业务逻辑应优先匹配枚举分支。

## 扩展位置

- 框架适配器：在独立包中将 HTTP、任务或消息调用包装为 `ActionOutcome`。
- 配置来源：读取文件或环境变量后传入 `parse_config`。
- 指标出口：消费 `MetricsSnapshot`，或使用 Prometheus 文本导出器。
- 调度器：根据 `BulkheadQueued` 维护异步等待和超时。
