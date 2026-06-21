///|
pub(all) enum EventKind {
  ExecutionStarted
  ExecutionSucceeded
  ExecutionFailed
  RetryScheduledEvent
  CircuitOpenedEvent
  CircuitHalfOpenedEvent
  CircuitClosedEvent
  RateLimitGrantedEvent
  RateLimitRejectedEvent
  BulkheadEnteredEvent
  BulkheadQueuedEvent
  BulkheadRejectedEvent
  BulkheadReleasedEvent
} derive(Eq, Debug)

///|
pub(all) struct ResilienceEvent {
  kind : EventKind
  at_ms : Int
  operation : String
  detail : String
  value : Int
} derive(Eq, Debug)

///|
pub(all) struct EventLog {
  events : Array[ResilienceEvent]
  max_events : Int
  dropped_events : Int
} derive(Eq, Debug)

///|
pub(all) struct MetricCounter {
  name : String
  value : Int
} derive(Eq, Debug)

///|
pub(all) struct Metrics {
  counters : Array[MetricCounter]
  latency_count : Int
  latency_total_ms : Int
  latency_max_ms : Int
} derive(Eq, Debug)

///|
pub(all) struct MetricsSnapshot {
  executions : Int
  successes : Int
  failures : Int
  retries : Int
  circuit_opens : Int
  rate_limit_rejections : Int
  bulkhead_rejections : Int
  average_latency_ms : Int
  max_latency_ms : Int
  custom : Array[MetricCounter]
} derive(Eq, Debug)

///|
pub fn resilience_event(
  kind : EventKind,
  at_ms : Int,
  operation : String,
  detail : String,
  value : Int,
) -> ResilienceEvent {
  { kind, at_ms: clamp_non_negative(at_ms), operation, detail, value }
}

///|
pub fn new_event_log(max_events : Int) -> EventLog {
  { events: [], max_events: clamp_at_least_one(max_events), dropped_events: 0 }
}

///|
pub fn record_event(log : EventLog, event : ResilienceEvent) -> EventLog {
  let events = log.events.copy()
  let dropped = log.dropped_events
  if events.length() >= log.max_events {
    let next : Array[ResilienceEvent] = []
    for index = 1; index < events.length(); index = index + 1 {
      next.push(events[index])
    }
    next.push(event)
    return { ..log, events: next, dropped_events: dropped + 1 }
  }
  events.push(event)
  { ..log, events, dropped_events: dropped }
}

///|
pub fn event_log_clear(log : EventLog) -> EventLog {
  { ..log, events: [], dropped_events: 0 }
}

///|
pub fn event_log_filter(log : EventLog, kind : EventKind) -> EventLog {
  let events : Array[ResilienceEvent] = []
  for event in log.events {
    if event.kind == kind {
      events.push(event)
    }
  }
  { events, max_events: log.max_events, dropped_events: 0 }
}

///|
pub fn event_kind_name(kind : EventKind) -> String {
  match kind {
    ExecutionStarted => "execution.started"
    ExecutionSucceeded => "execution.succeeded"
    ExecutionFailed => "execution.failed"
    RetryScheduledEvent => "retry.scheduled"
    CircuitOpenedEvent => "circuit.opened"
    CircuitHalfOpenedEvent => "circuit.half_opened"
    CircuitClosedEvent => "circuit.closed"
    RateLimitGrantedEvent => "rate_limit.granted"
    RateLimitRejectedEvent => "rate_limit.rejected"
    BulkheadEnteredEvent => "bulkhead.entered"
    BulkheadQueuedEvent => "bulkhead.queued"
    BulkheadRejectedEvent => "bulkhead.rejected"
    BulkheadReleasedEvent => "bulkhead.released"
  }
}

///|
pub fn format_event(event : ResilienceEvent) -> String {
  let suffix = if event.detail.length() > 0 { " " + event.detail } else { "" }
  event.at_ms.to_string() +
  " " +
  event_kind_name(event.kind) +
  " operation=" +
  event.operation +
  " value=" +
  event.value.to_string() +
  suffix
}

///|
pub fn new_metrics() -> Metrics {
  { counters: [], latency_count: 0, latency_total_ms: 0, latency_max_ms: 0 }
}

///|
pub fn metrics_increment(
  metrics : Metrics,
  name : String,
  amount : Int,
) -> Metrics {
  let counters : Array[MetricCounter] = []
  let mut found = false
  for counter in metrics.counters {
    if counter.name == name {
      counters.push({ name, value: counter.value + amount })
      found = true
    } else {
      counters.push(counter)
    }
  }
  if !found {
    counters.push({ name, value: amount })
  }
  { ..metrics, counters, }
}

///|
pub fn metrics_observe_latency(metrics : Metrics, latency_ms : Int) -> Metrics {
  let value = clamp_non_negative(latency_ms)
  {
    ..metrics,
    latency_count: metrics.latency_count + 1,
    latency_total_ms: metrics.latency_total_ms + value,
    latency_max_ms: max_int(metrics.latency_max_ms, value),
  }
}

///|
pub fn metrics_record_event(
  metrics : Metrics,
  event : ResilienceEvent,
) -> Metrics {
  match event.kind {
    ExecutionStarted => metrics_increment(metrics, "executions", 1)
    ExecutionSucceeded => metrics_increment(metrics, "successes", 1)
    ExecutionFailed => metrics_increment(metrics, "failures", 1)
    RetryScheduledEvent => metrics_increment(metrics, "retries", 1)
    CircuitOpenedEvent => metrics_increment(metrics, "circuit_opens", 1)
    RateLimitRejectedEvent =>
      metrics_increment(metrics, "rate_limit_rejections", 1)
    BulkheadRejectedEvent =>
      metrics_increment(metrics, "bulkhead_rejections", 1)
    _ => metrics
  }
}

///|
pub fn metrics_from_log(log : EventLog) -> Metrics {
  let mut metrics = new_metrics()
  for event in log.events {
    metrics = metrics_record_event(metrics, event)
  }
  metrics
}

///|
pub fn metrics_counter(metrics : Metrics, name : String) -> Int {
  for counter in metrics.counters {
    if counter.name == name {
      return counter.value
    }
  }
  0
}

///|
pub fn metrics_snapshot(metrics : Metrics) -> MetricsSnapshot {
  {
    executions: metrics_counter(metrics, "executions"),
    successes: metrics_counter(metrics, "successes"),
    failures: metrics_counter(metrics, "failures"),
    retries: metrics_counter(metrics, "retries"),
    circuit_opens: metrics_counter(metrics, "circuit_opens"),
    rate_limit_rejections: metrics_counter(metrics, "rate_limit_rejections"),
    bulkhead_rejections: metrics_counter(metrics, "bulkhead_rejections"),
    average_latency_ms: if metrics.latency_count == 0 {
      0
    } else {
      metrics.latency_total_ms / metrics.latency_count
    },
    max_latency_ms: metrics.latency_max_ms,
    custom: metrics.counters.copy(),
  }
}

///|
pub fn format_metrics_snapshot(snapshot : MetricsSnapshot) -> String {
  "executions=" +
  snapshot.executions.to_string() +
  " successes=" +
  snapshot.successes.to_string() +
  " failures=" +
  snapshot.failures.to_string() +
  " retries=" +
  snapshot.retries.to_string() +
  " circuit_opens=" +
  snapshot.circuit_opens.to_string() +
  " rate_limit_rejections=" +
  snapshot.rate_limit_rejections.to_string() +
  " bulkhead_rejections=" +
  snapshot.bulkhead_rejections.to_string() +
  " average_latency_ms=" +
  snapshot.average_latency_ms.to_string() +
  " max_latency_ms=" +
  snapshot.max_latency_ms.to_string()
}

///|
pub fn trace_to_event_log(
  trace : ExecutionTrace,
  operation : String,
  started_at_ms : Int,
) -> EventLog {
  let mut log = new_event_log(max_int(1, trace.steps.length()))
  for index = 0; index < trace.steps.length(); index = index + 1 {
    let step = trace.steps[index]
    log = record_event(
      log,
      resilience_event(
        event_kind_from_trace(step),
        started_at_ms,
        operation,
        step,
        1,
      ),
    )
  }
  log
}

///|
fn event_kind_from_trace(step : String) -> EventKind {
  if step.contains("execution.started") {
    ExecutionStarted
  } else if step.contains("attempt.succeeded") {
    ExecutionSucceeded
  } else if step.contains("execution.failed") {
    ExecutionFailed
  } else if step.contains("retry.scheduled") {
    RetryScheduledEvent
  } else if step.contains("breaker.half_open") {
    CircuitHalfOpenedEvent
  } else if step.contains("breaker.rejected") {
    CircuitOpenedEvent
  } else if step.contains("rate_limit.rejected") {
    RateLimitRejectedEvent
  } else if step.contains("rate_limit.granted") {
    RateLimitGrantedEvent
  } else if step.contains("bulkhead.rejected") {
    BulkheadRejectedEvent
  } else if step.contains("bulkhead.queued") {
    BulkheadQueuedEvent
  } else if step.contains("bulkhead.released") {
    BulkheadReleasedEvent
  } else {
    BulkheadEnteredEvent
  }
}
