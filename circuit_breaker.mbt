///|
pub(all) enum BreakerState {
  Closed
  Open
  HalfOpen
} derive(Eq, Debug)

///|
pub(all) struct CircuitBreakerConfig {
  failure_threshold : Int
  success_threshold : Int
  open_window_ms : Int
  half_open_max_calls : Int
} derive(Eq, Debug)

///|
pub(all) struct CircuitBreaker {
  config : CircuitBreakerConfig
  state : BreakerState
  consecutive_failures : Int
  half_open_successes : Int
  half_open_in_flight : Int
  opened_at_ms : Int
  open_until_ms : Int
  transition_count : Int
} derive(Eq, Debug)

///|
pub(all) struct BreakerSnapshot {
  state : BreakerState
  consecutive_failures : Int
  half_open_successes : Int
  half_open_in_flight : Int
  open_until_ms : Int
  remaining_open_ms : Int
  transition_count : Int
} derive(Eq, Debug)

///|
pub(all) enum BreakerDecision {
  BreakerAllowed(CircuitBreaker, Bool)
  BreakerRejected(CircuitBreaker, Int, String)
} derive(Eq, Debug)

///|
pub fn circuit_breaker_config(
  failure_threshold : Int,
  success_threshold : Int,
  open_window_ms : Int,
  half_open_max_calls : Int,
) -> CircuitBreakerConfig {
  {
    failure_threshold: clamp_at_least_one(failure_threshold),
    success_threshold: clamp_at_least_one(success_threshold),
    open_window_ms: clamp_non_negative(open_window_ms),
    half_open_max_calls: clamp_at_least_one(half_open_max_calls),
  }
}

///|
pub fn default_circuit_breaker() -> CircuitBreaker {
  new_circuit_breaker(circuit_breaker_config(5, 2, 30000, 1))
}

///|
pub fn new_circuit_breaker(config : CircuitBreakerConfig) -> CircuitBreaker {
  {
    config: circuit_breaker_config(
      config.failure_threshold,
      config.success_threshold,
      config.open_window_ms,
      config.half_open_max_calls,
    ),
    state: Closed,
    consecutive_failures: 0,
    half_open_successes: 0,
    half_open_in_flight: 0,
    opened_at_ms: 0,
    open_until_ms: 0,
    transition_count: 0,
  }
}

///|
pub fn breaker_before_call(
  breaker : CircuitBreaker,
  now_ms : Int,
) -> BreakerDecision {
  match breaker.state {
    Closed => BreakerAllowed(breaker, false)
    Open =>
      if now_ms < breaker.open_until_ms {
        BreakerRejected(
          breaker,
          breaker.open_until_ms,
          "recovery window has not elapsed",
        )
      } else {
        let half_open = to_half_open(breaker)
        reserve_half_open_probe(half_open, true)
      }
    HalfOpen => reserve_half_open_probe(breaker, false)
  }
}

///|
pub fn breaker_record_success(
  breaker : CircuitBreaker,
  _now_ms : Int,
) -> CircuitBreaker {
  match breaker.state {
    Closed => { ..breaker, consecutive_failures: 0 }
    Open => breaker
    HalfOpen => {
      let remaining = max_int(0, breaker.half_open_in_flight - 1)
      let successes = breaker.half_open_successes + 1
      if successes >= breaker.config.success_threshold {
        close_breaker(breaker)
      } else {
        {
          ..breaker,
          half_open_successes: successes,
          half_open_in_flight: remaining,
        }
      }
    }
  }
}

///|
pub fn breaker_record_failure(
  breaker : CircuitBreaker,
  now_ms : Int,
) -> CircuitBreaker {
  match breaker.state {
    Open => breaker
    HalfOpen => open_breaker(breaker, now_ms)
    Closed => {
      let failures = breaker.consecutive_failures + 1
      if failures >= breaker.config.failure_threshold {
        open_breaker({ ..breaker, consecutive_failures: failures }, now_ms)
      } else {
        { ..breaker, consecutive_failures: failures }
      }
    }
  }
}

///|
pub fn breaker_cancel_call(breaker : CircuitBreaker) -> CircuitBreaker {
  match breaker.state {
    HalfOpen =>
      {
        ..breaker,
        half_open_in_flight: max_int(0, breaker.half_open_in_flight - 1),
      }
    _ => breaker
  }
}

///|
pub fn breaker_force_open(
  breaker : CircuitBreaker,
  now_ms : Int,
) -> CircuitBreaker {
  open_breaker(breaker, now_ms)
}

///|
pub fn breaker_force_close(breaker : CircuitBreaker) -> CircuitBreaker {
  close_breaker(breaker)
}

///|
pub fn breaker_snapshot(
  breaker : CircuitBreaker,
  now_ms : Int,
) -> BreakerSnapshot {
  {
    state: breaker.state,
    consecutive_failures: breaker.consecutive_failures,
    half_open_successes: breaker.half_open_successes,
    half_open_in_flight: breaker.half_open_in_flight,
    open_until_ms: breaker.open_until_ms,
    remaining_open_ms: if breaker.state == Open {
      max_int(0, breaker.open_until_ms - now_ms)
    } else {
      0
    },
    transition_count: breaker.transition_count,
  }
}

///|
pub fn breaker_state_name(state : BreakerState) -> String {
  match state {
    Closed => "closed"
    Open => "open"
    HalfOpen => "half-open"
  }
}

///|
pub fn format_breaker_snapshot(snapshot : BreakerSnapshot) -> String {
  "state=" +
  breaker_state_name(snapshot.state) +
  " failures=" +
  snapshot.consecutive_failures.to_string() +
  " half_open_successes=" +
  snapshot.half_open_successes.to_string() +
  " half_open_in_flight=" +
  snapshot.half_open_in_flight.to_string() +
  " remaining_open_ms=" +
  snapshot.remaining_open_ms.to_string() +
  " transitions=" +
  snapshot.transition_count.to_string()
}

///|
fn reserve_half_open_probe(
  breaker : CircuitBreaker,
  transitioned : Bool,
) -> BreakerDecision {
  if breaker.half_open_in_flight >= breaker.config.half_open_max_calls {
    BreakerRejected(
      breaker,
      breaker.open_until_ms,
      "half-open probe capacity exhausted",
    )
  } else {
    BreakerAllowed(
      { ..breaker, half_open_in_flight: breaker.half_open_in_flight + 1 },
      transitioned,
    )
  }
}

///|
fn to_half_open(breaker : CircuitBreaker) -> CircuitBreaker {
  {
    ..breaker,
    state: HalfOpen,
    consecutive_failures: 0,
    half_open_successes: 0,
    half_open_in_flight: 0,
    transition_count: breaker.transition_count + 1,
  }
}

///|
fn open_breaker(breaker : CircuitBreaker, now_ms : Int) -> CircuitBreaker {
  {
    ..breaker,
    state: Open,
    half_open_successes: 0,
    half_open_in_flight: 0,
    opened_at_ms: now_ms,
    open_until_ms: now_ms + breaker.config.open_window_ms,
    transition_count: breaker.transition_count + 1,
  }
}

///|
fn close_breaker(breaker : CircuitBreaker) -> CircuitBreaker {
  {
    ..breaker,
    state: Closed,
    consecutive_failures: 0,
    half_open_successes: 0,
    half_open_in_flight: 0,
    opened_at_ms: 0,
    open_until_ms: 0,
    transition_count: breaker.transition_count + 1,
  }
}
