///|
test "fixed exponential and linear backoff are deterministic" {
  assert_eq(
    @moonresilience.retry_delay(@moonresilience.fixed_backoff(40), 4),
    40,
  )
  assert_eq(
    @moonresilience.retry_delay(
      @moonresilience.exponential_backoff(100, 500),
      1,
    ),
    100,
  )
  assert_eq(
    @moonresilience.retry_delay(
      @moonresilience.exponential_backoff(100, 500),
      4,
    ),
    500,
  )
  assert_eq(
    @moonresilience.retry_delay(@moonresilience.linear_backoff(50, 25, 120), 4),
    120,
  )
}

///|
test "sequence backoff repeats the last delay" {
  let strategy = @moonresilience.sequence_backoff([10, 20, 45])
  assert_eq(@moonresilience.retry_delay(strategy, 1), 10)
  assert_eq(@moonresilience.retry_delay(strategy, 3), 45)
  assert_eq(@moonresilience.retry_delay(strategy, 8), 45)
}

///|
test "retry decision honors error code and elapsed time" {
  let policy = @moonresilience.retry_policy(
    5,
    250,
    @moonresilience.fixed_backoff(100),
    ["timeout"],
  )
  let timeout = @moonresilience.retryable_failure("timeout", "slow upstream")
  let denied = @moonresilience.retryable_failure("bad_request", "invalid")
  assert_true(@moonresilience.should_retry(policy, timeout, 1, 0))
  assert_false(@moonresilience.should_retry(policy, denied, 1, 0))
  assert_false(@moonresilience.should_retry(policy, timeout, 3, 200))
}

///|
test "permanent failure stops immediately" {
  let policy = @moonresilience.default_retry_policy()
  let failure = @moonresilience.permanent_failure("auth", "unauthorized")
  let snapshot = @moonresilience.retry_snapshot(policy, failure, 1, 0)
  assert_false(snapshot.can_retry)
  assert_eq(snapshot.stop_reason, "failure is permanent")
}

///|
test "total retry delay observes policy cap" {
  let policy = @moonresilience.retry_policy(
    6,
    450,
    @moonresilience.fixed_backoff(150),
    [],
  )
  assert_eq(@moonresilience.total_retry_delay(policy), 450)
}
