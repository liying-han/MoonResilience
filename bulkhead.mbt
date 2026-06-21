///|
pub(all) struct BulkheadConfig {
  max_concurrent : Int
  max_waiting : Int
} derive(Eq, Debug)

///|
pub(all) struct WaitingCall {
  call_id : String
  enqueued_at_ms : Int
} derive(Eq, Debug)

///|
pub(all) struct Bulkhead {
  config : BulkheadConfig
  active_calls : Array[String]
  waiting_calls : Array[WaitingCall]
  total_entered : Int
  total_queued : Int
  total_rejected : Int
  total_completed : Int
} derive(Eq, Debug)

///|
pub(all) enum BulkheadAdmission {
  BulkheadEntered(Bulkhead, Int)
  BulkheadQueued(Bulkhead, Int)
  BulkheadRejected(Bulkhead, String)
} derive(Eq, Debug)

///|
pub(all) struct BulkheadRelease {
  bulkhead : Bulkhead
  released : Bool
  promoted_call : String?
} derive(Eq, Debug)

///|
pub(all) struct BulkheadSnapshot {
  active : Int
  waiting : Int
  available : Int
  waiting_available : Int
  total_entered : Int
  total_queued : Int
  total_rejected : Int
  total_completed : Int
} derive(Eq, Debug)

///|
pub fn bulkhead_config(
  max_concurrent : Int,
  max_waiting : Int,
) -> BulkheadConfig {
  {
    max_concurrent: clamp_at_least_one(max_concurrent),
    max_waiting: clamp_non_negative(max_waiting),
  }
}

///|
pub fn new_bulkhead(config : BulkheadConfig) -> Bulkhead {
  {
    config: bulkhead_config(config.max_concurrent, config.max_waiting),
    active_calls: [],
    waiting_calls: [],
    total_entered: 0,
    total_queued: 0,
    total_rejected: 0,
    total_completed: 0,
  }
}

///|
pub fn default_bulkhead() -> Bulkhead {
  new_bulkhead(bulkhead_config(10, 20))
}

///|
pub fn bulkhead_admit(
  bulkhead : Bulkhead,
  call_id : String,
  now_ms : Int,
) -> BulkheadAdmission {
  if call_id.length() == 0 {
    return BulkheadRejected(
      { ..bulkhead, total_rejected: bulkhead.total_rejected + 1 },
      "call id must not be empty",
    )
  }
  if bulkhead_contains(bulkhead, call_id) {
    return BulkheadRejected(
      { ..bulkhead, total_rejected: bulkhead.total_rejected + 1 },
      "call id already exists",
    )
  }
  if bulkhead.active_calls.length() < bulkhead.config.max_concurrent {
    let active = bulkhead.active_calls.copy()
    active.push(call_id)
    BulkheadEntered(
      {
        ..bulkhead,
        active_calls: active,
        total_entered: bulkhead.total_entered + 1,
      },
      active.length(),
    )
  } else if bulkhead.waiting_calls.length() < bulkhead.config.max_waiting {
    let waiting = bulkhead.waiting_calls.copy()
    waiting.push({ call_id, enqueued_at_ms: clamp_non_negative(now_ms) })
    BulkheadQueued(
      {
        ..bulkhead,
        waiting_calls: waiting,
        total_queued: bulkhead.total_queued + 1,
      },
      waiting.length(),
    )
  } else {
    BulkheadRejected(
      { ..bulkhead, total_rejected: bulkhead.total_rejected + 1 },
      "concurrent and waiting capacity exhausted",
    )
  }
}

///|
pub fn bulkhead_complete(
  bulkhead : Bulkhead,
  call_id : String,
) -> BulkheadRelease {
  let active = remove_string(bulkhead.active_calls, call_id)
  if active.length() == bulkhead.active_calls.length() {
    return { bulkhead, released: false, promoted_call: None }
  }
  if bulkhead.waiting_calls.length() == 0 {
    return {
      bulkhead: {
        ..bulkhead,
        active_calls: active,
        total_completed: bulkhead.total_completed + 1,
      },
      released: true,
      promoted_call: None,
    }
  }
  let promoted = bulkhead.waiting_calls[0]
  let waiting = waiting_without_first(bulkhead.waiting_calls)
  active.push(promoted.call_id)
  {
    bulkhead: {
      ..bulkhead,
      active_calls: active,
      waiting_calls: waiting,
      total_entered: bulkhead.total_entered + 1,
      total_completed: bulkhead.total_completed + 1,
    },
    released: true,
    promoted_call: Some(promoted.call_id),
  }
}

///|
pub fn bulkhead_cancel_waiting(
  bulkhead : Bulkhead,
  call_id : String,
) -> Bulkhead {
  { ..bulkhead, waiting_calls: remove_waiting(bulkhead.waiting_calls, call_id) }
}

///|
pub fn bulkhead_wait_ms(
  bulkhead : Bulkhead,
  call_id : String,
  now_ms : Int,
) -> Int? {
  for waiting in bulkhead.waiting_calls {
    if waiting.call_id == call_id {
      return Some(max_int(0, now_ms - waiting.enqueued_at_ms))
    }
  }
  None
}

///|
pub fn bulkhead_contains(bulkhead : Bulkhead, call_id : String) -> Bool {
  if array_contains(bulkhead.active_calls, call_id) {
    return true
  }
  for waiting in bulkhead.waiting_calls {
    if waiting.call_id == call_id {
      return true
    }
  }
  false
}

///|
pub fn bulkhead_snapshot(bulkhead : Bulkhead) -> BulkheadSnapshot {
  {
    active: bulkhead.active_calls.length(),
    waiting: bulkhead.waiting_calls.length(),
    available: max_int(
      0,
      bulkhead.config.max_concurrent - bulkhead.active_calls.length(),
    ),
    waiting_available: max_int(
      0,
      bulkhead.config.max_waiting - bulkhead.waiting_calls.length(),
    ),
    total_entered: bulkhead.total_entered,
    total_queued: bulkhead.total_queued,
    total_rejected: bulkhead.total_rejected,
    total_completed: bulkhead.total_completed,
  }
}

///|
pub fn format_bulkhead_snapshot(snapshot : BulkheadSnapshot) -> String {
  "active=" +
  snapshot.active.to_string() +
  " waiting=" +
  snapshot.waiting.to_string() +
  " available=" +
  snapshot.available.to_string() +
  " rejected=" +
  snapshot.total_rejected.to_string() +
  " completed=" +
  snapshot.total_completed.to_string()
}

///|
fn remove_string(values : Array[String], target : String) -> Array[String] {
  let next : Array[String] = []
  for value in values {
    if value != target {
      next.push(value)
    }
  }
  next
}

///|
fn remove_waiting(
  values : Array[WaitingCall],
  target : String,
) -> Array[WaitingCall] {
  let next : Array[WaitingCall] = []
  for value in values {
    if value.call_id != target {
      next.push(value)
    }
  }
  next
}

///|
fn waiting_without_first(values : Array[WaitingCall]) -> Array[WaitingCall] {
  let next : Array[WaitingCall] = []
  for index = 1; index < values.length(); index = index + 1 {
    next.push(values[index])
  }
  next
}
