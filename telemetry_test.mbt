///|
test "event log keeps bounded newest events" {
  let mut log = @moonresilience.new_event_log(2)
  for index = 1; index <= 3; index = index + 1 {
    log = @moonresilience.record_event(
      log,
      @moonresilience.resilience_event(
        ExecutionStarted,
        index,
        "api",
        "",
        index,
      ),
    )
  }
  assert_eq(log.events.length(), 2)
  assert_eq(log.events[0].value, 2)
  assert_eq(log.dropped_events, 1)
}

///|
test "event log filters by kind" {
  let started = @moonresilience.resilience_event(
    ExecutionStarted,
    0,
    "api",
    "",
    1,
  )
  let failed = @moonresilience.resilience_event(
    ExecutionFailed,
    1,
    "api",
    "timeout",
    1,
  )
  let log = @moonresilience.record_event(
    @moonresilience.record_event(@moonresilience.new_event_log(5), started),
    failed,
  )
  let failures = @moonresilience.event_log_filter(log, ExecutionFailed)
  assert_eq(failures.events.length(), 1)
  assert_eq(failures.events[0].detail, "timeout")
}

///|
test "metrics aggregate standard event counters" {
  let mut log = @moonresilience.new_event_log(10)
  log = @moonresilience.record_event(
    log,
    @moonresilience.resilience_event(ExecutionStarted, 0, "api", "", 1),
  )
  log = @moonresilience.record_event(
    log,
    @moonresilience.resilience_event(RetryScheduledEvent, 5, "api", "", 1),
  )
  log = @moonresilience.record_event(
    log,
    @moonresilience.resilience_event(ExecutionSucceeded, 10, "api", "", 1),
  )
  let snapshot = @moonresilience.metrics_snapshot(
    @moonresilience.metrics_from_log(log),
  )
  assert_eq(snapshot.executions, 1)
  assert_eq(snapshot.successes, 1)
  assert_eq(snapshot.retries, 1)
}

///|
test "custom metric increments preserve other counters" {
  let first = @moonresilience.metrics_increment(
    @moonresilience.new_metrics(),
    "queue_depth",
    2,
  )
  let second = @moonresilience.metrics_increment(first, "queue_depth", 3)
  let third = @moonresilience.metrics_increment(second, "workers", 4)
  assert_eq(@moonresilience.metrics_counter(third, "queue_depth"), 5)
  assert_eq(@moonresilience.metrics_counter(third, "workers"), 4)
}

///|
test "latency metrics calculate average and maximum" {
  let first = @moonresilience.metrics_observe_latency(
    @moonresilience.new_metrics(),
    10,
  )
  let second = @moonresilience.metrics_observe_latency(first, 30)
  let snapshot = @moonresilience.metrics_snapshot(second)
  assert_eq(snapshot.average_latency_ms, 20)
  assert_eq(snapshot.max_latency_ms, 30)
}

///|
test "event formatting exposes stable fields" {
  let event = @moonresilience.resilience_event(
    CircuitOpenedEvent,
    42,
    "payment",
    "until=1042",
    1,
  )
  assert_eq(
    @moonresilience.format_event(event),
    "42 circuit.opened operation=payment value=1 until=1042",
  )
}

///|
test "execution trace converts to event log" {
  let result = @moonresilience.execute_with(
    chain_for_test(),
    @moonresilience.execution_context(0, "telemetry-call"),
    fn(_attempt, _now_ms) { Success("ok") },
  )
  let log = @moonresilience.trace_to_event_log(
    result.trace,
    "telemetry-call",
    0,
  )
  assert_true(log.events.length() >= 5)
  assert_true(log.events[0].kind is ExecutionStarted)
}

///|
test "formatted metric snapshot is concise" {
  let metrics = @moonresilience.metrics_increment(
    @moonresilience.new_metrics(),
    "executions",
    2,
  )
  assert_true(
    @moonresilience.format_metrics_snapshot(
      @moonresilience.metrics_snapshot(metrics),
    ).contains("executions=2 successes=0"),
  )
}
