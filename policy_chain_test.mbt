///|
fn chain_for_test() -> @moonresilience.PolicyChain {
  @moonresilience.policy_chain(
    @moonresilience.retry_policy(3, 1000, @moonresilience.fixed_backoff(50), []),
    @moonresilience.new_circuit_breaker(
      @moonresilience.circuit_breaker_config(5, 1, 1000, 1),
    ),
    TokenBucketPolicy(
      @moonresilience.new_token_bucket(
        @moonresilience.token_bucket_config(10, 10, 1000),
        0,
      ),
    ),
    @moonresilience.new_bulkhead(@moonresilience.bulkhead_config(1, 0)),
  )
}

///|
test "policy chain returns successful action" {
  let result = @moonresilience.execute_with(
    chain_for_test(),
    @moonresilience.execution_context(0, "call-1"),
    fn(_attempt, _now_ms) { Success("ok") },
  )
  match result.outcome {
    Ok(value) => assert_eq(value, "ok")
    Err(err) => abort(@moonresilience.format_execute_error(err))
  }
  assert_eq(result.attempts, 1)
  assert_eq(result.chain.bulkhead.active_calls.length(), 0)
}

///|
test "policy chain retries retryable failure" {
  let result = @moonresilience.execute_with(
    chain_for_test(),
    @moonresilience.execution_context(100, "call-2"),
    fn(attempt, _now_ms) {
      if attempt < 3 {
        Failure(@moonresilience.retryable_failure("timeout", "temporary"))
      } else {
        Success("recovered")
      }
    },
  )
  assert_true(@moonresilience.execution_succeeded(result))
  assert_eq(result.attempts, 3)
  assert_eq(result.finished_at_ms, 200)
  assert_eq(@moonresilience.execution_duration_ms(result), 100)
}

///|
test "permanent failure stops without retry" {
  let result = @moonresilience.execute_with(
    chain_for_test(),
    @moonresilience.execution_context(0, "call-3"),
    fn(_attempt, _now_ms) -> @moonresilience.ActionOutcome[String] {
      Failure(@moonresilience.permanent_failure("invalid", "bad input"))
    },
  )
  assert_eq(result.attempts, 1)
  match result.outcome {
    Err(RetryExhausted(code, _, attempts)) => {
      assert_eq(code, "invalid")
      assert_eq(attempts, 1)
    }
    _ => abort("expected action failure")
  }
}

///|
test "rate limit rejection happens before action" {
  let base = chain_for_test()
  let empty = @moonresilience.token_bucket_with_tokens(
    @moonresilience.token_bucket_config(1, 1, 1000),
    0,
    0,
  )
  let chain = { ..base, rate_limit: TokenBucketPolicy(empty) }
  let result = @moonresilience.execute_with(
    chain,
    @moonresilience.execution_context(0, "call-4"),
    fn(_attempt, _now_ms) { Success("must-not-run") },
  )
  assert_eq(result.attempts, 0)
  match result.outcome {
    Err(RejectedByRateLimiter(reason)) =>
      assert_true(reason.contains("retry_after_ms=1000"))
    _ => abort("expected rate limit")
  }
}

///|
test "bulkhead rejection follows rate limit grant" {
  let base = chain_for_test()
  let occupied = match
    @moonresilience.bulkhead_admit(base.bulkhead, "busy", 0) {
    BulkheadEntered(current, _) => current
    _ => abort("expected occupied bulkhead")
  }
  let chain = { ..base, bulkhead: occupied }
  let result = @moonresilience.execute_with(
    chain,
    @moonresilience.execution_context(0, "call-5"),
    fn(_attempt, _now_ms) { Success("must-not-run") },
  )
  match result.outcome {
    Err(RejectedByBulkhead(reason)) => assert_true(reason.contains("capacity"))
    _ => abort("expected bulkhead rejection")
  }
  assert_true(result.trace.steps[1].contains("rate_limit.granted"))
}

///|
test "open breaker releases bulkhead reservation" {
  let base = chain_for_test()
  let chain = {
    ..base,
    breaker: @moonresilience.breaker_force_open(base.breaker, 0),
  }
  let result = @moonresilience.execute_with(
    chain,
    @moonresilience.execution_context(10, "call-6"),
    fn(_attempt, _now_ms) { Success("must-not-run") },
  )
  match result.outcome {
    Err(RejectedByCircuitBreaker(until_ms)) => assert_eq(until_ms, 1000)
    _ => abort("expected open circuit")
  }
  assert_eq(result.chain.bulkhead.active_calls.length(), 0)
}

///|
test "execution trace preserves policy order" {
  let result = @moonresilience.execute_with(
    chain_for_test(),
    @moonresilience.execution_context(0, "call-7"),
    fn(_attempt, _now_ms) { Success("ok") },
  )
  let text = @moonresilience.execution_trace_text(result.trace)
  assert_true(text.contains("execution.started"))
  assert_true(text.contains("rate_limit.granted"))
  assert_true(text.contains("bulkhead.entered"))
  assert_true(text.contains("attempt.succeeded"))
  assert_true(text.contains("bulkhead.released"))
}
