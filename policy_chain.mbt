///|
pub(all) enum RateLimitPolicy {
  TokenBucketPolicy(TokenBucket)
  FixedWindowPolicy(FixedWindowLimiter)
} derive(Eq, Debug)

///|
pub(all) struct PolicyChain {
  retry : RetryPolicy
  breaker : CircuitBreaker
  rate_limit : RateLimitPolicy
  bulkhead : Bulkhead
} derive(Eq, Debug)

///|
pub(all) struct ExecutionTrace {
  steps : Array[String]
} derive(Eq, Debug)

///|
pub(all) struct ExecutionResult[T] {
  outcome : Result[T, ExecuteError]
  chain : PolicyChain
  attempts : Int
  started_at_ms : Int
  finished_at_ms : Int
  trace : ExecutionTrace
}

///|
priv struct AdmissionResult {
  chain : PolicyChain
  error : ExecuteError?
}

///|
pub fn default_policy_chain(now_ms : Int) -> PolicyChain {
  {
    retry: default_retry_policy(),
    breaker: default_circuit_breaker(),
    rate_limit: TokenBucketPolicy(
      new_token_bucket(token_bucket_config(100, 100, 1000), now_ms),
    ),
    bulkhead: default_bulkhead(),
  }
}

///|
pub fn policy_chain(
  retry : RetryPolicy,
  breaker : CircuitBreaker,
  rate_limit : RateLimitPolicy,
  bulkhead : Bulkhead,
) -> PolicyChain {
  { retry, breaker, rate_limit, bulkhead }
}

///|
pub fn empty_execution_trace() -> ExecutionTrace {
  { steps: [] }
}

///|
pub fn[T] execute_with(
  chain : PolicyChain,
  context : ExecutionContext,
  action : (Int, Int) -> ActionOutcome[T],
) -> ExecutionResult[T] {
  let trace = empty_execution_trace()
  trace_step(trace, "execution.started operation=" + context.operation)
  let admitted = admit_chain(chain, context, trace)
  match admitted.error {
    Some(err) => {
      trace_step(trace, "execution.rejected " + format_execute_error(err))
      {
        outcome: Err(err),
        chain: admitted.chain,
        attempts: 0,
        started_at_ms: context.now_ms,
        finished_at_ms: context.now_ms,
        trace,
      }
    }
    None => run_chain_attempt(admitted.chain, context, 1, trace, action)
  }
}

///|
pub fn[T] execution_succeeded(result : ExecutionResult[T]) -> Bool {
  result.outcome is Ok(_)
}

///|
pub fn[T] execution_duration_ms(result : ExecutionResult[T]) -> Int {
  max_int(0, result.finished_at_ms - result.started_at_ms)
}

///|
pub fn execution_trace_text(trace : ExecutionTrace) -> String {
  let mut output = ""
  for index = 0; index < trace.steps.length(); index = index + 1 {
    if index > 0 {
      output = output + "\n"
    }
    output = output + trace.steps[index]
  }
  output
}

///|
fn[T] run_chain_attempt(
  chain : PolicyChain,
  context : ExecutionContext,
  attempt : Int,
  trace : ExecutionTrace,
  action : (Int, Int) -> ActionOutcome[T],
) -> ExecutionResult[T] {
  let now_ms = attempt_time(chain.retry, context.now_ms, attempt)
  match breaker_before_call(chain.breaker, now_ms) {
    BreakerRejected(breaker, until_ms, reason) => {
      trace_step(
        trace,
        "breaker.rejected until_ms=" + until_ms.to_string() + " " + reason,
      )
      finish_chain_error(
        with_chain_breaker(chain, breaker),
        context,
        attempt - 1,
        now_ms,
        trace,
        RejectedByCircuitBreaker(until_ms),
      )
    }
    BreakerAllowed(breaker, transitioned) => {
      if transitioned {
        trace_step(trace, "breaker.half_open")
      }
      trace_step(
        trace,
        "attempt.started number=" +
        attempt.to_string() +
        " at_ms=" +
        now_ms.to_string(),
      )
      let current = with_chain_breaker(chain, breaker)
      match action(attempt, now_ms) {
        Success(value) => {
          let succeeded = breaker_record_success(current.breaker, now_ms)
          trace_step(trace, "attempt.succeeded number=" + attempt.to_string())
          let released = release_chain_bulkhead(
            with_chain_breaker(current, succeeded),
            context.operation,
            trace,
          )
          {
            outcome: Ok(value),
            chain: released,
            attempts: attempt,
            started_at_ms: context.now_ms,
            finished_at_ms: now_ms,
            trace,
          }
        }
        Failure(failure) => {
          let failed_breaker = breaker_record_failure(current.breaker, now_ms)
          let failed = with_chain_breaker(current, failed_breaker)
          trace_step(
            trace,
            "attempt.failed number=" +
            attempt.to_string() +
            " code=" +
            failure.code,
          )
          if should_retry(
              failed.retry,
              failure,
              attempt,
              now_ms - context.now_ms,
            ) {
            trace_step(
              trace,
              "retry.scheduled delay_ms=" +
              retry_delay(failed.retry.backoff, attempt).to_string(),
            )
            run_chain_attempt(failed, context, attempt + 1, trace, action)
          } else {
            finish_chain_error(
              failed,
              context,
              attempt,
              now_ms,
              trace,
              RetryExhausted(failure.code, failure.message, attempt),
            )
          }
        }
      }
    }
  }
}

///|
fn admit_chain(
  chain : PolicyChain,
  context : ExecutionContext,
  trace : ExecutionTrace,
) -> AdmissionResult {
  let (limited, decision) = acquire_rate_limit(chain.rate_limit, context.now_ms)
  let limited_chain = with_chain_rate_limit(chain, limited)
  if !decision.allowed {
    trace_step(trace, "rate_limit.rejected " + decision.reason)
    return {
      chain: limited_chain,
      error: Some(
        RejectedByRateLimiter(
          decision.reason +
          " retry_after_ms=" +
          decision.retry_after_ms.to_string(),
        ),
      ),
    }
  }
  trace_step(
    trace,
    "rate_limit.granted remaining=" + decision.remaining.to_string(),
  )
  match
    bulkhead_admit(limited_chain.bulkhead, context.operation, context.now_ms) {
    BulkheadEntered(bulkhead, active) => {
      trace_step(trace, "bulkhead.entered active=" + active.to_string())
      { chain: with_chain_bulkhead(limited_chain, bulkhead), error: None }
    }
    BulkheadQueued(bulkhead, position) => {
      trace_step(trace, "bulkhead.queued position=" + position.to_string())
      {
        chain: with_chain_bulkhead(limited_chain, bulkhead),
        error: Some(
          RejectedByBulkhead("queued at position " + position.to_string()),
        ),
      }
    }
    BulkheadRejected(bulkhead, reason) => {
      trace_step(trace, "bulkhead.rejected " + reason)
      {
        chain: with_chain_bulkhead(limited_chain, bulkhead),
        error: Some(RejectedByBulkhead(reason)),
      }
    }
  }
}

///|
fn acquire_rate_limit(
  policy : RateLimitPolicy,
  now_ms : Int,
) -> (RateLimitPolicy, RateLimitDecision) {
  match policy {
    TokenBucketPolicy(bucket) => {
      let result = token_bucket_acquire(bucket, 1, now_ms)
      (TokenBucketPolicy(result.bucket), result.decision)
    }
    FixedWindowPolicy(limiter) => {
      let result = fixed_window_acquire(limiter, 1, now_ms)
      (FixedWindowPolicy(result.limiter), result.decision)
    }
  }
}

///|
fn[T] finish_chain_error(
  chain : PolicyChain,
  context : ExecutionContext,
  attempts : Int,
  finished_at_ms : Int,
  trace : ExecutionTrace,
  err : ExecuteError,
) -> ExecutionResult[T] {
  trace_step(trace, "execution.failed " + format_execute_error(err))
  let released = release_chain_bulkhead(chain, context.operation, trace)
  {
    outcome: Err(err),
    chain: released,
    attempts,
    started_at_ms: context.now_ms,
    finished_at_ms,
    trace,
  }
}

///|
fn release_chain_bulkhead(
  chain : PolicyChain,
  call_id : String,
  trace : ExecutionTrace,
) -> PolicyChain {
  let release = bulkhead_complete(chain.bulkhead, call_id)
  if release.released {
    trace_step(trace, "bulkhead.released")
  }
  with_chain_bulkhead(chain, release.bulkhead)
}

///|
fn attempt_time(
  policy : RetryPolicy,
  started_at_ms : Int,
  attempt : Int,
) -> Int {
  let mut elapsed = 0
  for completed = 1; completed < attempt; completed = completed + 1 {
    elapsed = elapsed + retry_delay(policy.backoff, completed)
  }
  started_at_ms + elapsed
}

///|
fn with_chain_breaker(
  chain : PolicyChain,
  breaker : CircuitBreaker,
) -> PolicyChain {
  { ..chain, breaker, }
}

///|
fn with_chain_rate_limit(
  chain : PolicyChain,
  rate_limit : RateLimitPolicy,
) -> PolicyChain {
  { ..chain, rate_limit, }
}

///|
fn with_chain_bulkhead(chain : PolicyChain, bulkhead : Bulkhead) -> PolicyChain {
  { ..chain, bulkhead, }
}

///|
fn trace_step(trace : ExecutionTrace, step : String) -> Unit {
  trace.steps.push(step)
}
