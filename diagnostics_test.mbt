///|
test "healthy default chain reports available capacity" {
  let snapshot = @moonresilience.inspect_policy_chain(
    @moonresilience.default_policy_chain(0),
    0,
  )
  assert_true(snapshot.health is Healthy)
  assert_eq(snapshot.limiter_remaining, 100)
  assert_eq(snapshot.bulkhead.available, 10)
  assert_eq(snapshot.violations.length(), 0)
}

///|
test "open circuit reports unavailable health" {
  let base = @moonresilience.default_policy_chain(0)
  let chain = {
    ..base,
    breaker: @moonresilience.breaker_force_open(base.breaker, 0),
  }
  let snapshot = @moonresilience.inspect_policy_chain(chain, 10)
  assert_true(snapshot.health is Unavailable)
  assert_eq(snapshot.breaker.remaining_open_ms, 29990)
}

///|
test "empty token bucket reports degraded health" {
  let base = @moonresilience.default_policy_chain(0)
  let bucket = @moonresilience.token_bucket_with_tokens(
    @moonresilience.token_bucket_config(2, 1, 100),
    0,
    0,
  )
  let chain = { ..base, rate_limit: TokenBucketPolicy(bucket) }
  let snapshot = @moonresilience.inspect_policy_chain(chain, 0)
  assert_true(snapshot.health is Degraded)
  assert_eq(snapshot.limiter_retry_after_ms, 100)
}

///|
test "full bulkhead reports degraded health" {
  let base = @moonresilience.default_policy_chain(0)
  let small = @moonresilience.new_bulkhead(
    @moonresilience.bulkhead_config(1, 0),
  )
  let occupied = match @moonresilience.bulkhead_admit(small, "busy", 0) {
    BulkheadEntered(current, _) => current
    _ => abort("expected admission")
  }
  let snapshot = @moonresilience.inspect_policy_chain(
    { ..base, bulkhead: occupied },
    0,
  )
  assert_true(snapshot.health is Degraded)
  assert_eq(snapshot.bulkhead.available, 0)
}

///|
test "invariant checker identifies malformed token bucket" {
  let base = @moonresilience.default_policy_chain(0)
  let bucket : @moonresilience.TokenBucket = {
    config: @moonresilience.token_bucket_config(2, 1, 100),
    available_tokens: 5,
    last_refill_ms: 0,
    total_granted: 0,
    total_rejected: 0,
  }
  let violations = @moonresilience.check_policy_invariants({
    ..base,
    rate_limit: TokenBucketPolicy(bucket),
  })
  assert_eq(violations.length(), 1)
  assert_eq(violations[0].component, "token_bucket")
}

///|
test "invariant checker identifies duplicate bulkhead membership" {
  let base = @moonresilience.default_policy_chain(0)
  let bulkhead : @moonresilience.Bulkhead = {
    config: @moonresilience.bulkhead_config(2, 2),
    active_calls: ["same"],
    waiting_calls: [{ call_id: "same", enqueued_at_ms: 0 }],
    total_entered: 1,
    total_queued: 1,
    total_rejected: 0,
    total_completed: 0,
  }
  let violations = @moonresilience.check_policy_invariants({ ..base, bulkhead, })
  assert_true(
    @moonresilience.format_invariant_violations(violations).contains(
      "active and waiting",
    ),
  )
}

///|
test "policy snapshot formatting remains concise" {
  let text = @moonresilience.format_policy_snapshot(
    @moonresilience.inspect_policy_chain(
      @moonresilience.default_policy_chain(0),
      50,
    ),
  )
  assert_true(text.contains("health=healthy at_ms=50 breaker=closed"))
  assert_true(text.contains("violations=0"))
}

///|
test "empty violation list has explicit text" {
  assert_eq(
    @moonresilience.format_invariant_violations([]),
    "no invariant violations",
  )
}

///|
test "registry adds and finds named policy" {
  let chain = @moonresilience.default_policy_chain(0)
  let registry = match
    @moonresilience.registry_add(
      @moonresilience.new_policy_registry(),
      "http-client",
      chain,
      description="client defaults",
    ) {
    Ok(value) => value
    Err(err) => abort(@moonresilience.format_registry_error(err))
  }
  assert_true(@moonresilience.registry_contains(registry, "http-client"))
  assert_eq(@moonresilience.registry_names(registry)[0], "http-client")
  match @moonresilience.registry_find(registry, "http-client") {
    Ok(found) => assert_eq(found.retry.max_attempts, 3)
    Err(err) => abort(@moonresilience.format_registry_error(err))
  }
}

///|
test "registry rejects duplicate and empty names" {
  let chain = @moonresilience.default_policy_chain(0)
  match
    @moonresilience.registry_add(
      @moonresilience.new_policy_registry(),
      "",
      chain,
    ) {
    Err(EmptyPolicyName) => ()
    _ => abort("expected empty name")
  }
  let registry = match
    @moonresilience.registry_add(
      @moonresilience.new_policy_registry(),
      "worker",
      chain,
    ) {
    Ok(value) => value
    _ => abort("expected registry")
  }
  match @moonresilience.registry_add(registry, "worker", chain) {
    Err(DuplicatePolicyName(name)) => assert_eq(name, "worker")
    _ => abort("expected duplicate")
  }
}

///|
test "registry default follows set and removal" {
  let chain = @moonresilience.default_policy_chain(0)
  let added = match
    @moonresilience.registry_add(
      @moonresilience.new_policy_registry(),
      "default",
      chain,
    ) {
    Ok(value) => value
    _ => abort("expected added policy")
  }
  let selected = match @moonresilience.registry_set_default(added, "default") {
    Ok(value) => value
    _ => abort("expected default selection")
  }
  match @moonresilience.registry_default(selected) {
    Ok(value) => assert_eq(value.retry.max_attempts, 3)
    _ => abort("expected default policy")
  }
  let removed = match @moonresilience.registry_remove(selected, "default") {
    Ok(value) => value
    _ => abort("expected removal")
  }
  match @moonresilience.registry_default(removed) {
    Err(DefaultPolicyNotFound(_)) => ()
    _ => abort("expected unset default")
  }
}

///|
test "registry replaces existing policy" {
  let first = @moonresilience.default_policy_chain(0)
  let second = {
    ..first,
    retry: @moonresilience.retry_policy(
      7,
      100,
      @moonresilience.fixed_backoff(1),
      [],
    ),
  }
  let added = match
    @moonresilience.registry_add(
      @moonresilience.new_policy_registry(),
      "worker",
      first,
    ) {
    Ok(value) => value
    _ => abort("expected added policy")
  }
  let replaced = match
    @moonresilience.registry_replace(added, "worker", second) {
    Ok(value) => value
    _ => abort("expected replacement")
  }
  match @moonresilience.registry_find(replaced, "worker") {
    Ok(found) => assert_eq(found.retry.max_attempts, 7)
    _ => abort("expected replaced policy")
  }
}
