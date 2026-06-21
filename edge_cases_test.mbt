///|
test "retry backoff matrix is monotonic and capped" {
  let strategy = @moonresilience.exponential_backoff(25, 200)
  let expected = [25, 50, 100, 200, 200, 200]
  for index = 0; index < expected.length(); index = index + 1 {
    assert_eq(@moonresilience.retry_delay(strategy, index + 1), expected[index])
  }
}

///|
test "linear backoff matrix grows by fixed step" {
  let strategy = @moonresilience.linear_backoff(10, 15, 60)
  let expected = [10, 25, 40, 55, 60]
  for index = 0; index < expected.length(); index = index + 1 {
    assert_eq(@moonresilience.retry_delay(strategy, index + 1), expected[index])
  }
}

///|
test "retry code filter tests allowed and denied codes" {
  let policy = @moonresilience.retry_policy(
    3,
    1000,
    @moonresilience.fixed_backoff(1),
    ["timeout", "busy"],
  )
  let cases = [
    ("timeout", true),
    ("busy", true),
    ("invalid", false),
    ("permission", false),
  ]
  for item in cases {
    assert_eq(
      @moonresilience.should_retry(
        policy,
        @moonresilience.retryable_failure(item.0, "failure"),
        1,
        0,
      ),
      item.1,
    )
  }
}

///|
test "breaker thresholds from one to four open exactly on boundary" {
  for threshold = 1; threshold <= 4; threshold = threshold + 1 {
    let mut breaker = @moonresilience.new_circuit_breaker(
      @moonresilience.circuit_breaker_config(threshold, 1, 100, 1),
    )
    for failure = 1; failure <= threshold; failure = failure + 1 {
      breaker = @moonresilience.breaker_record_failure(breaker, failure)
      if failure < threshold {
        assert_true(breaker.state is Closed)
      } else {
        assert_true(breaker.state is Open)
      }
    }
  }
}

///|
test "token bucket grants every capacity from one to eight" {
  for capacity = 1; capacity <= 8; capacity = capacity + 1 {
    let bucket = @moonresilience.new_token_bucket(
      @moonresilience.token_bucket_config(capacity, 1, 100),
      0,
    )
    let result = @moonresilience.token_bucket_acquire(bucket, capacity, 0)
    assert_true(result.decision.allowed)
    assert_eq(result.decision.remaining, 0)
  }
}

///|
test "fixed window resets across multiple skipped windows" {
  let limiter = @moonresilience.new_fixed_window_limiter(
    @moonresilience.fixed_window_config(1, 100),
    0,
  )
  let used = @moonresilience.fixed_window_acquire(limiter, 1, 0)
  let rolled = @moonresilience.roll_fixed_window(used.limiter, 550)
  assert_eq(rolled.window_started_ms, 500)
  assert_eq(rolled.used, 0)
}

///|
test "bulkhead promotes queued calls in FIFO order" {
  let mut bulkhead = @moonresilience.new_bulkhead(
    @moonresilience.bulkhead_config(1, 3),
  )
  bulkhead = match @moonresilience.bulkhead_admit(bulkhead, "a", 0) {
    BulkheadEntered(value, _) => value
    _ => abort("expected a")
  }
  for pair in [("b", 1), ("c", 2), ("d", 3)] {
    bulkhead = match @moonresilience.bulkhead_admit(bulkhead, pair.0, pair.1) {
      BulkheadQueued(value, _) => value
      _ => abort("expected queue")
    }
  }
  let first = @moonresilience.bulkhead_complete(bulkhead, "a")
  let second = @moonresilience.bulkhead_complete(first.bulkhead, "b")
  assert_eq(first.bulkhead.active_calls[0], "b")
  assert_eq(second.bulkhead.active_calls[0], "c")
}

///|
test "config accepts every supported backoff kind" {
  for kind in ["fixed", "linear", "exponential"] {
    let config = match @moonresilience.parse_config("retry.backoff=" + kind) {
      Ok(value) => value
      Err(err) => abort(@moonresilience.format_config_error(err))
    }
    match @moonresilience.config_to_policy_chain(config, 0) {
      Ok(chain) => assert_eq(chain.retry.max_attempts, 3)
      Err(err) => abort(@moonresilience.format_config_error(err))
    }
  }
}

///|
test "event log zero capacity is normalized to one" {
  let log = @moonresilience.new_event_log(0)
  assert_eq(log.max_events, 1)
}

///|
test "negative latency observation is normalized" {
  let metrics = @moonresilience.metrics_observe_latency(
    @moonresilience.new_metrics(),
    -10,
  )
  let snapshot = @moonresilience.metrics_snapshot(metrics)
  assert_eq(snapshot.average_latency_ms, 0)
  assert_eq(snapshot.max_latency_ms, 0)
}

///|
test "policy chain fixed-window variant executes" {
  let base = chain_for_test()
  let chain = {
    ..base,
    rate_limit: FixedWindowPolicy(
      @moonresilience.new_fixed_window_limiter(
        @moonresilience.fixed_window_config(2, 100),
        0,
      ),
    ),
  }
  let result = @moonresilience.execute_with(
    chain,
    @moonresilience.execution_context(0, "fixed-window-call"),
    fn(_attempt, _now) { Success("ok") },
  )
  assert_true(@moonresilience.execution_succeeded(result))
}

///|
test "trace failure converts to failure metric" {
  let result = @moonresilience.execute_with(
    chain_for_test(),
    @moonresilience.execution_context(0, "failed-call"),
    fn(_attempt, _now) -> @moonresilience.ActionOutcome[String] {
      Failure(@moonresilience.permanent_failure("bad", "bad"))
    },
  )
  let log = @moonresilience.trace_to_event_log(result.trace, "failed-call", 0)
  let metrics = @moonresilience.metrics_snapshot(
    @moonresilience.metrics_from_log(log),
  )
  assert_eq(metrics.executions, 1)
  assert_eq(metrics.failures, 1)
}
