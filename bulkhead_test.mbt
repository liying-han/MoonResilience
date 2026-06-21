///|
fn small_bulkhead() -> @moonresilience.Bulkhead {
  @moonresilience.new_bulkhead(@moonresilience.bulkhead_config(1, 1))
}

///|
test "bulkhead admits within concurrent capacity" {
  match @moonresilience.bulkhead_admit(small_bulkhead(), "a", 0) {
    BulkheadEntered(current, active) => {
      assert_eq(active, 1)
      assert_eq(current.active_calls[0], "a")
    }
    _ => abort("expected direct admission")
  }
}

///|
test "bulkhead queues after active capacity is full" {
  let active = match @moonresilience.bulkhead_admit(small_bulkhead(), "a", 0) {
    BulkheadEntered(current, _) => current
    _ => abort("expected first admission")
  }
  match @moonresilience.bulkhead_admit(active, "b", 25) {
    BulkheadQueued(current, waiting) => {
      assert_eq(waiting, 1)
      assert_eq(current.waiting_calls[0].call_id, "b")
      assert_eq(current.total_queued, 1)
    }
    _ => abort("expected queue")
  }
}

///|
test "bulkhead rejects when all capacity is exhausted" {
  let active = match @moonresilience.bulkhead_admit(small_bulkhead(), "a", 0) {
    BulkheadEntered(current, _) => current
    _ => abort("expected admission")
  }
  let queued = match @moonresilience.bulkhead_admit(active, "b", 1) {
    BulkheadQueued(current, _) => current
    _ => abort("expected queue")
  }
  match @moonresilience.bulkhead_admit(queued, "c", 2) {
    BulkheadRejected(current, reason) => {
      assert_eq(reason, "concurrent and waiting capacity exhausted")
      assert_eq(current.total_rejected, 1)
    }
    _ => abort("expected rejection")
  }
}

///|
test "completing active call promotes first waiter" {
  let active = match @moonresilience.bulkhead_admit(small_bulkhead(), "a", 0) {
    BulkheadEntered(current, _) => current
    _ => abort("expected admission")
  }
  let queued = match @moonresilience.bulkhead_admit(active, "b", 10) {
    BulkheadQueued(current, _) => current
    _ => abort("expected queue")
  }
  let release = @moonresilience.bulkhead_complete(queued, "a")
  assert_true(release.released)
  match release.promoted_call {
    Some(call_id) => assert_eq(call_id, "b")
    None => abort("expected promoted call")
  }
  assert_eq(release.bulkhead.active_calls[0], "b")
  assert_eq(release.bulkhead.waiting_calls.length(), 0)
}

///|
test "unknown completion does not mutate bulkhead" {
  let release = @moonresilience.bulkhead_complete(small_bulkhead(), "missing")
  assert_false(release.released)
  assert_eq(release.bulkhead.total_completed, 0)
}

///|
test "queued call reports deterministic wait duration" {
  let active = match @moonresilience.bulkhead_admit(small_bulkhead(), "a", 0) {
    BulkheadEntered(current, _) => current
    _ => abort("expected admission")
  }
  let queued = match @moonresilience.bulkhead_admit(active, "b", 10) {
    BulkheadQueued(current, _) => current
    _ => abort("expected queue")
  }
  match @moonresilience.bulkhead_wait_ms(queued, "b", 45) {
    Some(wait_ms) => assert_eq(wait_ms, 35)
    None => abort("expected wait duration")
  }
}

///|
test "cancel removes waiting call" {
  let active = match @moonresilience.bulkhead_admit(small_bulkhead(), "a", 0) {
    BulkheadEntered(current, _) => current
    _ => abort("expected admission")
  }
  let queued = match @moonresilience.bulkhead_admit(active, "b", 10) {
    BulkheadQueued(current, _) => current
    _ => abort("expected queue")
  }
  let cancelled = @moonresilience.bulkhead_cancel_waiting(queued, "b")
  assert_false(@moonresilience.bulkhead_contains(cancelled, "b"))
}

///|
test "duplicate and empty ids are rejected" {
  match @moonresilience.bulkhead_admit(small_bulkhead(), "", 0) {
    BulkheadRejected(_, reason) =>
      assert_eq(reason, "call id must not be empty")
    _ => abort("expected empty rejection")
  }
  let active = match @moonresilience.bulkhead_admit(small_bulkhead(), "a", 0) {
    BulkheadEntered(current, _) => current
    _ => abort("expected admission")
  }
  match @moonresilience.bulkhead_admit(active, "a", 1) {
    BulkheadRejected(_, reason) => assert_eq(reason, "call id already exists")
    _ => abort("expected duplicate rejection")
  }
}
