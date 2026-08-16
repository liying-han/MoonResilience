///|
test "config validation rejects every numeric boundary" {
  let cases = [
    ("retry.max_attempts=0", "retry.max_attempts"),
    ("retry.max_elapsed_ms=-1", "retry.max_elapsed_ms"),
    ("retry.base_delay_ms=-1", "retry.base_delay_ms"),
    ("breaker.failure_threshold=0", "breaker.failure_threshold"),
    ("breaker.success_threshold=0", "breaker.success_threshold"),
    ("breaker.open_window_ms=-1", "breaker.open_window_ms"),
    ("breaker.half_open_max_calls=0", "breaker.half_open_max_calls"),
    ("limiter.capacity=0", "limiter.capacity"),
    ("limiter.refill_tokens=0", "limiter.refill_tokens"),
    ("limiter.window_ms=0", "limiter.window_ms"),
    ("bulkhead.max_concurrent=0", "bulkhead.max_concurrent"),
    ("bulkhead.max_waiting=-1", "bulkhead.max_waiting"),
  ]
  for item in cases {
    match @moonresilience.parse_config(item.0) {
      Err(ConfigConstraint(key, _)) => assert_eq(key, item.1)
      _ => abort("expected constraint for " + item.1)
    }
  }
}

///|
test "config validation reports unsupported backoff and invalid chain" {
  match @moonresilience.parse_config("retry.backoff=quadratic") {
    Err(ConfigConstraint(key, message)) => {
      assert_eq(key, "retry.backoff")
      assert_true(message.contains("fixed"))
    }
    _ => abort("expected unsupported backoff")
  }
  let invalid = { ..@moonresilience.default_config(), retry_max_attempts: 0 }
  match @moonresilience.config_to_policy_chain(invalid, 0) {
    Err(ConfigConstraint(key, _)) => assert_eq(key, "retry.max_attempts")
    Ok(_) => abort("expected invalid chain")
    _ => abort("expected configuration constraint")
  }
}

///|
test "breaker no-op states and names are stable" {
  let breaker = @moonresilience.new_circuit_breaker(
    @moonresilience.circuit_breaker_config(2, 1, 100, 1),
  )
  assert_eq(@moonresilience.breaker_state_name(Closed), "closed")
  assert_eq(@moonresilience.breaker_state_name(Open), "open")
  assert_eq(@moonresilience.breaker_state_name(HalfOpen), "half-open")
  let opened = @moonresilience.breaker_force_open(breaker, 0)
  assert_true(@moonresilience.breaker_record_success(opened, 1).state is Open)
  assert_true(@moonresilience.breaker_record_failure(opened, 1).state is Open)
  assert_true(@moonresilience.breaker_force_close(opened).state is Closed)
  assert_true(@moonresilience.breaker_cancel_call(breaker).state is Closed)
}

///|
test "bulkhead waiting membership and snapshot formatting" {
  let base = @moonresilience.new_bulkhead(@moonresilience.bulkhead_config(1, 1))
  let active = match @moonresilience.bulkhead_admit(base, "active", 0) {
    BulkheadEntered(value, _) => value
    _ => abort("expected active call")
  }
  let queued = match @moonresilience.bulkhead_admit(active, "waiting", 10) {
    BulkheadQueued(value, _) => value
    _ => abort("expected waiting call")
  }
  assert_true(@moonresilience.bulkhead_contains(queued, "waiting"))
  assert_false(@moonresilience.bulkhead_contains(queued, "missing"))
  let snapshot = @moonresilience.bulkhead_snapshot(queued)
  assert_eq(snapshot.active, 1)
  assert_eq(snapshot.waiting, 1)
  assert_true(
    @moonresilience.format_bulkhead_snapshot(snapshot).contains(
      "active=1 waiting=1",
    ),
  )
}

///|
test "rate limiter resets and formats both decisions" {
  let bucket = @moonresilience.new_token_bucket(
    @moonresilience.token_bucket_config(2, 1, 100),
    0,
  )
  let consumed = @moonresilience.token_bucket_acquire(bucket, 2, 0).bucket
  let reset = @moonresilience.token_bucket_reset(consumed, -10)
  assert_eq(reset.available_tokens, 2)
  assert_eq(reset.last_refill_ms, 0)
  let limiter = @moonresilience.new_fixed_window_limiter(
    @moonresilience.fixed_window_config(1, 100),
    10,
  )
  let reset_window = @moonresilience.fixed_window_reset(limiter, -5)
  assert_eq(reset_window.window_started_ms, 0)
  assert_eq(reset_window.used, 0)
  let allowed : @moonresilience.RateLimitDecision = {
    allowed: true,
    remaining: 1,
    retry_after_ms: 0,
    reason: "granted",
  }
  assert_eq(
    @moonresilience.format_rate_limit_decision(allowed),
    "allowed remaining=1",
  )
}

///|
test "registry reports missing operations and formats errors" {
  let empty = @moonresilience.new_policy_registry()
  match @moonresilience.registry_default(empty) {
    Err(DefaultPolicyNotFound(name)) => assert_eq(name, "<unset>")
    _ => abort("expected unset default")
  }
  match @moonresilience.registry_set_default(empty, "missing") {
    Err(DefaultPolicyNotFound(name)) => assert_eq(name, "missing")
    _ => abort("expected missing default")
  }
  let chain = @moonresilience.default_policy_chain(0)
  match @moonresilience.registry_replace(empty, "missing", chain) {
    Err(PolicyNotFound(name)) => assert_eq(name, "missing")
    _ => abort("expected missing replacement")
  }
  match @moonresilience.registry_remove(empty, "missing") {
    Err(PolicyNotFound(name)) => assert_eq(name, "missing")
    _ => abort("expected missing removal")
  }
  assert_eq(
    @moonresilience.format_registry_error(EmptyPolicyName),
    "policy name must not be empty",
  )
}

///|
test "event log retains bounded history and maps event kinds" {
  let kinds = [
    @moonresilience.ExecutionStarted,
    @moonresilience.ExecutionSucceeded,
    @moonresilience.ExecutionFailed,
    @moonresilience.RetryScheduledEvent,
    @moonresilience.CircuitOpenedEvent,
    @moonresilience.CircuitHalfOpenedEvent,
    @moonresilience.CircuitClosedEvent,
    @moonresilience.RateLimitGrantedEvent,
    @moonresilience.RateLimitRejectedEvent,
    @moonresilience.BulkheadEnteredEvent,
    @moonresilience.BulkheadQueuedEvent,
    @moonresilience.BulkheadRejectedEvent,
    @moonresilience.BulkheadReleasedEvent,
  ]
  for kind in kinds {
    assert_true(@moonresilience.event_kind_name(kind).length() > 0)
  }
  let event = @moonresilience.resilience_event(
    @moonresilience.ExecutionFailed,
    -1,
    "op",
    "failed",
    2,
  )
  assert_eq(event.at_ms, 0)
  let log = @moonresilience.record_event(
    @moonresilience.record_event(@moonresilience.new_event_log(1), event),
    @moonresilience.resilience_event(
      @moonresilience.ExecutionSucceeded,
      3,
      "op",
      "",
      0,
    ),
  )
  assert_eq(log.events.length(), 1)
  assert_eq(log.dropped_events, 1)
  assert_eq(
    @moonresilience.event_log_filter(log, @moonresilience.ExecutionFailed).events.length(),
    0,
  )
  assert_eq(@moonresilience.event_log_clear(log).dropped_events, 0)
  assert_true(@moonresilience.format_event(event).contains("execution.failed"))
}

///|
test "latency and prometheus exporters reject invalid input" {
  let left = @moonresilience.latency_observe(
    @moonresilience.new_latency_histogram([10]),
    5,
  )
  let right = @moonresilience.latency_observe(
    @moonresilience.new_latency_histogram([20]),
    15,
  )
  match @moonresilience.latency_merge(left, right) {
    Err(message) => assert_true(message.contains("different bucket"))
    Ok(_) => abort("expected incompatible histogram")
  }
  assert_eq(@moonresilience.latency_percentile(left, 0), 10)
  assert_eq(@moonresilience.latency_percentile(left, 101), 10)
  let metrics = @moonresilience.metrics_snapshot(@moonresilience.new_metrics())
  match @moonresilience.export_prometheus(metrics, prefix="bad-name") {
    Err(message) => assert_true(message.contains("invalid metric prefix"))
    Ok(_) => abort("expected invalid metric prefix")
  }
  match
    @moonresilience.export_prometheus(metrics, labels=[
      @moonresilience.metric_label("ok", "line\nfeed"),
    ]) {
    Err(message) => assert_true(message.contains("newline"))
    Ok(_) => abort("expected invalid label")
  }
}

///|
test "diagnostic names and latency empty cases are explicit" {
  assert_eq(@moonresilience.health_level_name(Healthy), "healthy")
  assert_eq(@moonresilience.health_level_name(Degraded), "degraded")
  assert_eq(@moonresilience.health_level_name(Unavailable), "unavailable")
  let violations : Array[@moonresilience.InvariantViolation] = [
    { component: "breaker", message: "open" },
    { component: "limiter", message: "empty" },
  ]
  assert_true(
    @moonresilience.format_invariant_violations(violations).contains(
      "breaker: open\nlimiter: empty",
    ),
  )
  let empty = @moonresilience.new_latency_histogram([10])
  assert_eq(@moonresilience.latency_percentile(empty, 50), 0)
  let observed = @moonresilience.latency_observe(empty, 20)
  assert_eq(observed.overflow_count, 1)
  match @moonresilience.latency_merge(empty, observed) {
    Ok(merged) => assert_eq(merged.min_ms, 20)
    Err(message) => abort(message)
  }
}

///|
test "batch stops on failure and exposes summary helpers" {
  let requests = [
    @moonresilience.batch_request(
      "ok",
      @moonresilience.simulation_scenario("ok", "op", 0, [
        @moonresilience.simulated_success("ok", 1),
      ]),
    ),
    @moonresilience.batch_request(
      "bad",
      @moonresilience.simulation_scenario("bad", "op", 0, [
        @moonresilience.simulated_failure("bad", "bad", false, 1),
      ]),
    ),
    @moonresilience.batch_request(
      "skipped",
      @moonresilience.simulation_scenario("skipped", "op", 0, [
        @moonresilience.simulated_success("skip", 1),
      ]),
    ),
  ]
  let batch = @moonresilience.run_batch(
    @moonresilience.default_policy_chain(0),
    requests,
    stop_on_failure=true,
  )
  let summary = @moonresilience.batch_summary(batch)
  assert_eq(summary.total, 2)
  assert_eq(summary.succeeded, 1)
  assert_eq(summary.failed, 1)
  assert_true(summary.stopped_early)
  assert_true(@moonresilience.batch_find(batch, "bad") is Some(_))
  match @moonresilience.batch_find(batch, "skipped") {
    None => ()
    Some(_) => abort("expected skipped request to be absent")
  }
  assert_eq(@moonresilience.batch_failures(batch).length(), 1)
  assert_true(
    @moonresilience.format_batch_summary(summary).contains("failed=1"),
  )
}
