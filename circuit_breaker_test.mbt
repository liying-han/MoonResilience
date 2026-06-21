///|
fn test_breaker() -> @moonresilience.CircuitBreaker {
  @moonresilience.new_circuit_breaker(
    @moonresilience.circuit_breaker_config(2, 2, 1000, 1),
  )
}

///|
test "breaker opens after configured failure threshold" {
  let first = @moonresilience.breaker_record_failure(test_breaker(), 10)
  assert_true(first.state is Closed)
  assert_eq(first.consecutive_failures, 1)
  let second = @moonresilience.breaker_record_failure(first, 20)
  assert_true(second.state is Open)
  assert_eq(second.open_until_ms, 1020)
  assert_eq(second.transition_count, 1)
}

///|
test "open breaker rejects before recovery window" {
  let opened = @moonresilience.breaker_force_open(test_breaker(), 100)
  match @moonresilience.breaker_before_call(opened, 1099) {
    BreakerRejected(current, until_ms, reason) => {
      assert_true(current.state is Open)
      assert_eq(until_ms, 1100)
      assert_eq(reason, "recovery window has not elapsed")
    }
    _ => abort("expected rejection")
  }
}

///|
test "elapsed recovery window reserves one half-open probe" {
  let opened = @moonresilience.breaker_force_open(test_breaker(), 100)
  match @moonresilience.breaker_before_call(opened, 1100) {
    BreakerAllowed(current, transitioned) => {
      assert_true(current.state is HalfOpen)
      assert_true(transitioned)
      assert_eq(current.half_open_in_flight, 1)
      assert_eq(current.transition_count, 2)
    }
    _ => abort("expected probe")
  }
}

///|
test "half-open breaker limits concurrent probes" {
  let opened = @moonresilience.breaker_force_open(test_breaker(), 0)
  let first = match @moonresilience.breaker_before_call(opened, 1000) {
    BreakerAllowed(current, _) => current
    _ => abort("expected first probe")
  }
  match @moonresilience.breaker_before_call(first, 1000) {
    BreakerRejected(_, _, reason) =>
      assert_eq(reason, "half-open probe capacity exhausted")
    _ => abort("expected probe rejection")
  }
}

///|
test "successful probes close half-open breaker" {
  let config = @moonresilience.circuit_breaker_config(1, 2, 50, 1)
  let opened = @moonresilience.breaker_force_open(
    @moonresilience.new_circuit_breaker(config),
    0,
  )
  let probe1 = match @moonresilience.breaker_before_call(opened, 50) {
    BreakerAllowed(current, _) => current
    _ => abort("expected first probe")
  }
  let after1 = @moonresilience.breaker_record_success(probe1, 50)
  assert_true(after1.state is HalfOpen)
  let probe2 = match @moonresilience.breaker_before_call(after1, 51) {
    BreakerAllowed(current, _) => current
    _ => abort("expected second probe")
  }
  let closed = @moonresilience.breaker_record_success(probe2, 51)
  assert_true(closed.state is Closed)
  assert_eq(closed.transition_count, 3)
}

///|
test "failed half-open probe reopens recovery window" {
  let opened = @moonresilience.breaker_force_open(test_breaker(), 0)
  let probe = match @moonresilience.breaker_before_call(opened, 1000) {
    BreakerAllowed(current, _) => current
    _ => abort("expected probe")
  }
  let reopened = @moonresilience.breaker_record_failure(probe, 1005)
  assert_true(reopened.state is Open)
  assert_eq(reopened.open_until_ms, 2005)
  assert_eq(reopened.transition_count, 3)
}

///|
test "cancelled probe releases half-open capacity" {
  let opened = @moonresilience.breaker_force_open(test_breaker(), 0)
  let probe = match @moonresilience.breaker_before_call(opened, 1000) {
    BreakerAllowed(current, _) => current
    _ => abort("expected probe")
  }
  let cancelled = @moonresilience.breaker_cancel_call(probe)
  assert_eq(cancelled.half_open_in_flight, 0)
  match @moonresilience.breaker_before_call(cancelled, 1001) {
    BreakerAllowed(_, _) => ()
    _ => abort("expected capacity after cancellation")
  }
}

///|
test "snapshot reports remaining open duration" {
  let opened = @moonresilience.breaker_force_open(test_breaker(), 100)
  let snapshot = @moonresilience.breaker_snapshot(opened, 400)
  assert_eq(snapshot.remaining_open_ms, 700)
  assert_true(
    @moonresilience.format_breaker_snapshot(snapshot).contains(
      "state=open failures=0",
    ),
  )
}
