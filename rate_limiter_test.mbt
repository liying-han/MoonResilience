///|
test "token bucket starts full and grants permits" {
  let bucket = @moonresilience.new_token_bucket(
    @moonresilience.token_bucket_config(5, 2, 100),
    0,
  )
  let result = @moonresilience.token_bucket_acquire(bucket, 3, 0)
  assert_true(result.decision.allowed)
  assert_eq(result.decision.remaining, 2)
  assert_eq(result.bucket.total_granted, 3)
}

///|
test "token bucket rejects and reports retry delay" {
  let bucket = @moonresilience.token_bucket_with_tokens(
    @moonresilience.token_bucket_config(5, 2, 100),
    0,
    0,
  )
  let result = @moonresilience.token_bucket_acquire(bucket, 3, 20)
  assert_false(result.decision.allowed)
  assert_eq(result.decision.retry_after_ms, 180)
  assert_eq(result.bucket.total_rejected, 1)
}

///|
test "token bucket refills complete elapsed periods" {
  let bucket = @moonresilience.token_bucket_with_tokens(
    @moonresilience.token_bucket_config(5, 2, 100),
    0,
    0,
  )
  let current = @moonresilience.refill_token_bucket(bucket, 250)
  assert_eq(current.available_tokens, 4)
  assert_eq(current.last_refill_ms, 200)
}

///|
test "token bucket refill never exceeds capacity" {
  let bucket = @moonresilience.token_bucket_with_tokens(
    @moonresilience.token_bucket_config(5, 3, 100),
    4,
    0,
  )
  let current = @moonresilience.refill_token_bucket(bucket, 1000)
  assert_eq(current.available_tokens, 5)
}

///|
test "token bucket rejects impossible permit request" {
  let bucket = @moonresilience.new_token_bucket(
    @moonresilience.token_bucket_config(2, 1, 100),
    0,
  )
  let result = @moonresilience.token_bucket_acquire(bucket, 3, 0)
  assert_false(result.decision.allowed)
  assert_eq(result.decision.retry_after_ms, -1)
}

///|
test "fixed window grants until limit" {
  let limiter = @moonresilience.new_fixed_window_limiter(
    @moonresilience.fixed_window_config(3, 1000),
    0,
  )
  let first = @moonresilience.fixed_window_acquire(limiter, 2, 10)
  let second = @moonresilience.fixed_window_acquire(first.limiter, 1, 20)
  assert_true(second.decision.allowed)
  assert_eq(second.decision.remaining, 0)
  assert_eq(second.limiter.total_granted, 3)
}

///|
test "fixed window rejects with remaining duration" {
  let limiter = @moonresilience.new_fixed_window_limiter(
    @moonresilience.fixed_window_config(1, 1000),
    100,
  )
  let first = @moonresilience.fixed_window_acquire(limiter, 1, 200)
  let second = @moonresilience.fixed_window_acquire(first.limiter, 1, 300)
  assert_false(second.decision.allowed)
  assert_eq(second.decision.retry_after_ms, 800)
  assert_eq(second.limiter.total_rejected, 1)
}

///|
test "fixed window rolls forward at boundary" {
  let limiter = @moonresilience.new_fixed_window_limiter(
    @moonresilience.fixed_window_config(1, 100),
    0,
  )
  let used = @moonresilience.fixed_window_acquire(limiter, 1, 0)
  let renewed = @moonresilience.fixed_window_acquire(used.limiter, 1, 100)
  assert_true(renewed.decision.allowed)
  assert_eq(renewed.limiter.window_started_ms, 100)
}

///|
test "rate limit decision formatting is stable" {
  let decision : @moonresilience.RateLimitDecision = {
    allowed: false,
    remaining: 0,
    retry_after_ms: 45,
    reason: "insufficient tokens",
  }
  assert_eq(
    @moonresilience.format_rate_limit_decision(decision),
    "rejected reason=insufficient tokens remaining=0 retry_after_ms=45",
  )
}
