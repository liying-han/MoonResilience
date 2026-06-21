///|
pub(all) struct Tag {
  key : String
  value : String
} derive(Eq)

///|
pub(all) struct ExecutionContext {
  now_ms : Int
  operation : String
  tags : Array[Tag]
} derive(Eq)

///|
pub(all) struct AttemptFailure {
  code : String
  message : String
  retryable : Bool
} derive(Eq)

///|
pub(all) enum ActionOutcome[T] {
  Success(T)
  Failure(AttemptFailure)
}

///|
pub(all) enum ExecuteError {
  RejectedByRateLimiter(String)
  RejectedByCircuitBreaker(Int)
  RejectedByBulkhead(String)
  RetryExhausted(String, String, Int)
  InvalidPolicy(String)
} derive(Eq)

///|
pub fn execution_context(now_ms : Int, operation : String) -> ExecutionContext {
  { now_ms, operation, tags: [] }
}

///|
pub fn context_with_tag(
  context : ExecutionContext,
  key : String,
  value : String,
) -> ExecutionContext {
  let tags = context.tags.copy()
  tags.push({ key, value })
  { now_ms: context.now_ms, operation: context.operation, tags }
}

///|
pub fn retryable_failure(code : String, message : String) -> AttemptFailure {
  { code, message, retryable: true }
}

///|
pub fn permanent_failure(code : String, message : String) -> AttemptFailure {
  { code, message, retryable: false }
}

///|
pub fn format_execute_error(error : ExecuteError) -> String {
  match error {
    RejectedByRateLimiter(reason) => "rate limiter rejected: " + reason
    RejectedByCircuitBreaker(until_ms) =>
      "circuit breaker is open until " + until_ms.to_string() + "ms"
    RejectedByBulkhead(reason) => "bulkhead rejected: " + reason
    RetryExhausted(code, message, attempts) =>
      "retry exhausted after " +
      attempts.to_string() +
      " attempts [" +
      code +
      "]: " +
      message
    InvalidPolicy(message) => "invalid policy: " + message
  }
}

///|
fn clamp_non_negative(value : Int) -> Int {
  if value < 0 {
    0
  } else {
    value
  }
}

///|
fn clamp_at_least_one(value : Int) -> Int {
  if value <= 0 {
    1
  } else {
    value
  }
}

///|
fn min_int(left : Int, right : Int) -> Int {
  if left < right {
    left
  } else {
    right
  }
}

///|
fn max_int(left : Int, right : Int) -> Int {
  if left > right {
    left
  } else {
    right
  }
}

///|
fn array_contains(items : Array[String], target : String) -> Bool {
  for item in items {
    if item == target {
      return true
    }
  }
  false
}
