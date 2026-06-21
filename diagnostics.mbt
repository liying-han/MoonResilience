///|
pub(all) enum HealthLevel {
  Healthy
  Degraded
  Unavailable
} derive(Eq, Debug)

///|
pub(all) struct InvariantViolation {
  component : String
  message : String
} derive(Eq, Debug)

///|
pub(all) struct PolicySnapshot {
  at_ms : Int
  health : HealthLevel
  breaker : BreakerSnapshot
  limiter_kind : String
  limiter_remaining : Int
  limiter_retry_after_ms : Int
  bulkhead : BulkheadSnapshot
  violations : Array[InvariantViolation]
} derive(Eq, Debug)

///|
pub fn inspect_policy_chain(
  chain : PolicyChain,
  now_ms : Int,
) -> PolicySnapshot {
  let violations = check_policy_invariants(chain)
  let (kind, remaining, retry_after_ms) = inspect_limiter(
    chain.rate_limit,
    now_ms,
  )
  let breaker = breaker_snapshot(chain.breaker, now_ms)
  let bulkhead = bulkhead_snapshot(chain.bulkhead)
  {
    at_ms: clamp_non_negative(now_ms),
    health: calculate_health(breaker, remaining, bulkhead, violations),
    breaker,
    limiter_kind: kind,
    limiter_remaining: remaining,
    limiter_retry_after_ms: retry_after_ms,
    bulkhead,
    violations,
  }
}

///|
pub fn check_policy_invariants(
  chain : PolicyChain,
) -> Array[InvariantViolation] {
  let violations : Array[InvariantViolation] = []
  check_retry_invariants(chain.retry, violations)
  check_breaker_invariants(chain.breaker, violations)
  check_limiter_invariants(chain.rate_limit, violations)
  check_bulkhead_invariants(chain.bulkhead, violations)
  violations
}

///|
pub fn health_level_name(level : HealthLevel) -> String {
  match level {
    Healthy => "healthy"
    Degraded => "degraded"
    Unavailable => "unavailable"
  }
}

///|
pub fn format_policy_snapshot(snapshot : PolicySnapshot) -> String {
  "health=" +
  health_level_name(snapshot.health) +
  " at_ms=" +
  snapshot.at_ms.to_string() +
  " breaker=" +
  breaker_state_name(snapshot.breaker.state) +
  " limiter=" +
  snapshot.limiter_kind +
  " remaining=" +
  snapshot.limiter_remaining.to_string() +
  " bulkhead_active=" +
  snapshot.bulkhead.active.to_string() +
  " bulkhead_waiting=" +
  snapshot.bulkhead.waiting.to_string() +
  " violations=" +
  snapshot.violations.length().to_string()
}

///|
pub fn format_invariant_violations(
  violations : Array[InvariantViolation],
) -> String {
  if violations.length() == 0 {
    return "no invariant violations"
  }
  let mut output = ""
  for index = 0; index < violations.length(); index = index + 1 {
    if index > 0 {
      output = output + "\n"
    }
    let violation = violations[index]
    output = output + violation.component + ": " + violation.message
  }
  output
}

///|
fn inspect_limiter(
  policy : RateLimitPolicy,
  now_ms : Int,
) -> (String, Int, Int) {
  match policy {
    TokenBucketPolicy(bucket) => {
      let current = refill_token_bucket(bucket, now_ms)
      let retry_after = if current.available_tokens > 0 {
        0
      } else {
        token_bucket_acquire(current, 1, now_ms).decision.retry_after_ms
      }
      ("token_bucket", current.available_tokens, retry_after)
    }
    FixedWindowPolicy(limiter) => {
      let current = roll_fixed_window(limiter, now_ms)
      let remaining = max_int(0, current.config.limit - current.used)
      let retry_after = if remaining > 0 {
        0
      } else {
        max_int(
          0,
          current.window_started_ms + current.config.window_ms - now_ms,
        )
      }
      ("fixed_window", remaining, retry_after)
    }
  }
}

///|
fn calculate_health(
  breaker : BreakerSnapshot,
  limiter_remaining : Int,
  bulkhead : BulkheadSnapshot,
  violations : Array[InvariantViolation],
) -> HealthLevel {
  if violations.length() > 0 || breaker.state == Open {
    Unavailable
  } else if breaker.state == HalfOpen ||
    limiter_remaining == 0 ||
    bulkhead.available == 0 {
    Degraded
  } else {
    Healthy
  }
}

///|
fn check_retry_invariants(
  retry : RetryPolicy,
  violations : Array[InvariantViolation],
) -> Unit {
  if retry.max_attempts <= 0 {
    violations.push({
      component: "retry",
      message: "max_attempts must be positive",
    })
  }
  if retry.max_elapsed_ms < 0 {
    violations.push({
      component: "retry",
      message: "max_elapsed_ms must not be negative",
    })
  }
}

///|
fn check_breaker_invariants(
  breaker : CircuitBreaker,
  violations : Array[InvariantViolation],
) -> Unit {
  if breaker.config.failure_threshold <= 0 {
    violations.push({
      component: "circuit_breaker",
      message: "failure_threshold must be positive",
    })
  }
  if breaker.half_open_in_flight < 0 ||
    breaker.half_open_in_flight > breaker.config.half_open_max_calls {
    violations.push({
      component: "circuit_breaker",
      message: "half-open in-flight count is outside configured capacity",
    })
  }
  if breaker.state == Closed && breaker.open_until_ms != 0 {
    violations.push({
      component: "circuit_breaker",
      message: "closed breaker must not retain an open deadline",
    })
  }
}

///|
fn check_limiter_invariants(
  limiter : RateLimitPolicy,
  violations : Array[InvariantViolation],
) -> Unit {
  match limiter {
    TokenBucketPolicy(bucket) =>
      if bucket.available_tokens < 0 ||
        bucket.available_tokens > bucket.config.capacity {
        violations.push({
          component: "token_bucket",
          message: "available token count is outside capacity",
        })
      }
    FixedWindowPolicy(window) =>
      if window.used < 0 || window.used > window.config.limit {
        violations.push({
          component: "fixed_window",
          message: "used permit count is outside window limit",
        })
      }
  }
}

///|
fn check_bulkhead_invariants(
  bulkhead : Bulkhead,
  violations : Array[InvariantViolation],
) -> Unit {
  if bulkhead.active_calls.length() > bulkhead.config.max_concurrent {
    violations.push({
      component: "bulkhead",
      message: "active calls exceed concurrent capacity",
    })
  }
  if bulkhead.waiting_calls.length() > bulkhead.config.max_waiting {
    violations.push({
      component: "bulkhead",
      message: "waiting calls exceed queue capacity",
    })
  }
  for active in bulkhead.active_calls {
    for waiting in bulkhead.waiting_calls {
      if active == waiting.call_id {
        violations.push({
          component: "bulkhead",
          message: "call appears in active and waiting sets: " + active,
        })
      }
    }
  }
}
