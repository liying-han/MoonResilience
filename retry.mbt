///|
pub(all) enum BackoffStrategy {
  Fixed(Int)
  Exponential(Int, Int)
  Linear(Int, Int, Int)
  Sequence(Array[Int])
} derive(Eq, Debug)

///|
pub(all) struct RetryPolicy {
  max_attempts : Int
  max_elapsed_ms : Int
  backoff : BackoffStrategy
  retryable_codes : Array[String]
} derive(Eq, Debug)

///|
pub(all) struct RetrySnapshot {
  attempt : Int
  elapsed_ms : Int
  next_delay_ms : Int
  can_retry : Bool
  stop_reason : String
} derive(Eq, Debug)

///|
pub fn fixed_backoff(delay_ms : Int) -> BackoffStrategy {
  Fixed(clamp_non_negative(delay_ms))
}

///|
pub fn exponential_backoff(
  base_delay_ms : Int,
  max_delay_ms : Int,
) -> BackoffStrategy {
  let base = clamp_non_negative(base_delay_ms)
  Exponential(base, max_int(base, max_delay_ms))
}

///|
pub fn linear_backoff(
  initial_delay_ms : Int,
  step_ms : Int,
  max_delay_ms : Int,
) -> BackoffStrategy {
  let initial = clamp_non_negative(initial_delay_ms)
  let step = clamp_non_negative(step_ms)
  Linear(initial, step, max_int(initial, max_delay_ms))
}

///|
pub fn sequence_backoff(delays_ms : Array[Int]) -> BackoffStrategy {
  let normalized : Array[Int] = []
  for delay in delays_ms {
    normalized.push(clamp_non_negative(delay))
  }
  Sequence(normalized)
}

///|
pub fn default_retry_policy() -> RetryPolicy {
  {
    max_attempts: 3,
    max_elapsed_ms: 5000,
    backoff: exponential_backoff(100, 1000),
    retryable_codes: [],
  }
}

///|
pub fn retry_policy(
  max_attempts : Int,
  max_elapsed_ms : Int,
  backoff : BackoffStrategy,
  retryable_codes : Array[String],
) -> RetryPolicy {
  {
    max_attempts: clamp_at_least_one(max_attempts),
    max_elapsed_ms: clamp_non_negative(max_elapsed_ms),
    backoff,
    retryable_codes: retryable_codes.copy(),
  }
}

///|
pub fn retry_delay(strategy : BackoffStrategy, attempt : Int) -> Int {
  let safe_attempt = clamp_at_least_one(attempt)
  match strategy {
    Fixed(delay) => delay
    Exponential(base, cap) => exponential_delay(base, cap, safe_attempt - 1)
    Linear(initial, step, cap) =>
      min_int(cap, initial + step * (safe_attempt - 1))
    Sequence(delays) => sequence_delay(delays, safe_attempt - 1)
  }
}

///|
pub fn retry_snapshot(
  policy : RetryPolicy,
  failure : AttemptFailure,
  attempt : Int,
  elapsed_ms : Int,
) -> RetrySnapshot {
  let delay = retry_delay(policy.backoff, attempt)
  let attempts_left = attempt < policy.max_attempts
  let within_time = policy.max_elapsed_ms == 0 ||
    elapsed_ms + delay <= policy.max_elapsed_ms
  let code_allowed = policy.retryable_codes.length() == 0 ||
    array_contains(policy.retryable_codes, failure.code)
  if !failure.retryable {
    {
      attempt,
      elapsed_ms,
      next_delay_ms: delay,
      can_retry: false,
      stop_reason: "failure is permanent",
    }
  } else if !code_allowed {
    {
      attempt,
      elapsed_ms,
      next_delay_ms: delay,
      can_retry: false,
      stop_reason: "failure code is not allowed",
    }
  } else if !attempts_left {
    {
      attempt,
      elapsed_ms,
      next_delay_ms: delay,
      can_retry: false,
      stop_reason: "attempt limit reached",
    }
  } else if !within_time {
    {
      attempt,
      elapsed_ms,
      next_delay_ms: delay,
      can_retry: false,
      stop_reason: "elapsed time limit reached",
    }
  } else {
    {
      attempt,
      elapsed_ms,
      next_delay_ms: delay,
      can_retry: true,
      stop_reason: "",
    }
  }
}

///|
pub fn should_retry(
  policy : RetryPolicy,
  failure : AttemptFailure,
  attempt : Int,
  elapsed_ms : Int,
) -> Bool {
  retry_snapshot(policy, failure, attempt, elapsed_ms).can_retry
}

///|
pub fn total_retry_delay(policy : RetryPolicy) -> Int {
  total_retry_delay_from(policy, 1, 0)
}

///|
fn total_retry_delay_from(
  policy : RetryPolicy,
  attempt : Int,
  total : Int,
) -> Int {
  if attempt >= policy.max_attempts {
    total
  } else {
    let delay = retry_delay(policy.backoff, attempt)
    if policy.max_elapsed_ms > 0 && total + delay > policy.max_elapsed_ms {
      total
    } else {
      total_retry_delay_from(policy, attempt + 1, total + delay)
    }
  }
}

///|
fn exponential_delay(base : Int, cap : Int, steps : Int) -> Int {
  if steps <= 0 {
    min_int(base, cap)
  } else {
    exponential_delay(min_int(cap, base * 2), cap, steps - 1)
  }
}

///|
fn sequence_delay(delays : Array[Int], index : Int) -> Int {
  if delays.length() == 0 {
    0
  } else if index < delays.length() {
    delays[index]
  } else {
    delays[delays.length() - 1]
  }
}
