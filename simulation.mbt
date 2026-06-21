///|
pub(all) struct VirtualClock {
  now_ms : Int
  advances : Int
} derive(Eq, Debug)

///|
pub(all) enum SimulatedResponse {
  SimulatedSuccess(String, Int)
  SimulatedFailure(String, String, Bool, Int)
} derive(Eq, Debug)

///|
pub(all) struct SimulationScenario {
  name : String
  operation : String
  started_at_ms : Int
  responses : Array[SimulatedResponse]
  repeat_last : Bool
} derive(Eq, Debug)

///|
pub(all) struct TimelineEntry {
  at_ms : Int
  label : String
  detail : String
} derive(Eq, Debug)

///|
pub(all) struct SimulationResult {
  scenario : SimulationScenario
  outcome : Result[String, ExecuteError]
  chain : PolicyChain
  attempts : Int
  finished_at_ms : Int
  timeline : Array[TimelineEntry]
  events : EventLog
  metrics : MetricsSnapshot
} derive(Debug)

///|
pub fn virtual_clock(now_ms : Int) -> VirtualClock {
  { now_ms: clamp_non_negative(now_ms), advances: 0 }
}

///|
pub fn clock_advance(clock : VirtualClock, duration_ms : Int) -> VirtualClock {
  {
    now_ms: clock.now_ms + clamp_non_negative(duration_ms),
    advances: clock.advances + 1,
  }
}

///|
pub fn clock_advance_to(clock : VirtualClock, target_ms : Int) -> VirtualClock {
  if target_ms <= clock.now_ms {
    clock
  } else {
    { now_ms: target_ms, advances: clock.advances + 1 }
  }
}

///|
pub fn simulated_success(value : String, latency_ms : Int) -> SimulatedResponse {
  SimulatedSuccess(value, clamp_non_negative(latency_ms))
}

///|
pub fn simulated_failure(
  code : String,
  message : String,
  retryable : Bool,
  latency_ms : Int,
) -> SimulatedResponse {
  SimulatedFailure(code, message, retryable, clamp_non_negative(latency_ms))
}

///|
pub fn simulation_scenario(
  name : String,
  operation : String,
  started_at_ms : Int,
  responses : Array[SimulatedResponse],
  repeat_last? : Bool = false,
) -> SimulationScenario {
  {
    name,
    operation,
    started_at_ms: clamp_non_negative(started_at_ms),
    responses: responses.copy(),
    repeat_last,
  }
}

///|
pub fn simulate(
  chain : PolicyChain,
  scenario : SimulationScenario,
) -> SimulationResult {
  let execution = execute_with(
    chain,
    execution_context(scenario.started_at_ms, scenario.operation),
    fn(attempt, _now_ms) { scenario_outcome(scenario, attempt) },
  )
  let timeline = build_timeline(scenario, execution)
  let finished_at_ms = if timeline.length() == 0 {
    execution.finished_at_ms
  } else {
    timeline[timeline.length() - 1].at_ms
  }
  let events = trace_to_event_log(
    execution.trace,
    scenario.operation,
    scenario.started_at_ms,
  )
  let mut metric_state = metrics_from_log(events)
  metric_state = metrics_observe_latency(
    metric_state,
    max_int(0, finished_at_ms - scenario.started_at_ms),
  )
  {
    scenario,
    outcome: execution.outcome,
    chain: execution.chain,
    attempts: execution.attempts,
    finished_at_ms,
    timeline,
    events,
    metrics: metrics_snapshot(metric_state),
  }
}

///|
pub fn simulation_succeeded(result : SimulationResult) -> Bool {
  result.outcome is Ok(_)
}

///|
pub fn simulation_duration_ms(result : SimulationResult) -> Int {
  max_int(0, result.finished_at_ms - result.scenario.started_at_ms)
}

///|
pub fn timeline_filter(
  timeline : Array[TimelineEntry],
  label : String,
) -> Array[TimelineEntry] {
  let matches : Array[TimelineEntry] = []
  for entry in timeline {
    if entry.label == label {
      matches.push(entry)
    }
  }
  matches
}

///|
pub fn format_timeline(timeline : Array[TimelineEntry]) -> String {
  let mut output = ""
  for index = 0; index < timeline.length(); index = index + 1 {
    let entry = timeline[index]
    let suffix = if entry.detail.length() > 0 { " " + entry.detail } else { "" }
    if index > 0 {
      output = output + "\n"
    }
    output = output + entry.at_ms.to_string() + "ms " + entry.label + suffix
  }
  output
}

///|
pub fn format_simulation(result : SimulationResult) -> String {
  let status = match result.outcome {
    Ok(value) => "success value=" + value
    Err(err) => "failure " + format_execute_error(err)
  }
  "scenario=" +
  result.scenario.name +
  " status=" +
  status +
  " attempts=" +
  result.attempts.to_string() +
  " duration_ms=" +
  simulation_duration_ms(result).to_string() +
  "\n" +
  format_timeline(result.timeline) +
  "\nmetrics " +
  format_metrics_snapshot(result.metrics)
}

///|
pub fn run_scenarios(
  chain : PolicyChain,
  scenarios : Array[SimulationScenario],
) -> Array[SimulationResult] {
  let results : Array[SimulationResult] = []
  let mut current = chain
  for scenario in scenarios {
    let result = simulate(current, scenario)
    current = result.chain
    results.push(result)
  }
  results
}

///|
pub fn simulation_summary(results : Array[SimulationResult]) -> String {
  let mut succeeded = 0
  let mut failed = 0
  let mut attempts = 0
  let mut duration = 0
  for result in results {
    if simulation_succeeded(result) {
      succeeded = succeeded + 1
    } else {
      failed = failed + 1
    }
    attempts = attempts + result.attempts
    duration = duration + simulation_duration_ms(result)
  }
  "scenarios=" +
  results.length().to_string() +
  " succeeded=" +
  succeeded.to_string() +
  " failed=" +
  failed.to_string() +
  " attempts=" +
  attempts.to_string() +
  " virtual_duration_ms=" +
  duration.to_string()
}

///|
fn scenario_outcome(
  scenario : SimulationScenario,
  attempt : Int,
) -> ActionOutcome[String] {
  if scenario.responses.length() == 0 {
    return Failure(
      permanent_failure("empty_scenario", "scenario has no responses"),
    )
  }
  let index = attempt - 1
  if index >= scenario.responses.length() && !scenario.repeat_last {
    return Failure(
      permanent_failure(
        "scenario_exhausted",
        "scenario has no response for attempt " + attempt.to_string(),
      ),
    )
  }
  let selected = scenario.responses[min_int(
      index,
      scenario.responses.length() - 1,
    )]
  match selected {
    SimulatedSuccess(value, _) => Success(value)
    SimulatedFailure(code, message, retryable, _) =>
      Failure({ code, message, retryable })
  }
}

///|
fn build_timeline(
  scenario : SimulationScenario,
  execution : ExecutionResult[String],
) -> Array[TimelineEntry] {
  let timeline : Array[TimelineEntry] = []
  timeline.push({
    at_ms: scenario.started_at_ms,
    label: "scenario.started",
    detail: scenario.name,
  })
  let mut current_ms = scenario.started_at_ms
  for attempt = 1; attempt <= execution.attempts; attempt = attempt + 1 {
    if attempt > 1 {
      current_ms = current_ms +
        retry_delay(execution.chain.retry.backoff, attempt - 1)
    }
    let response = response_for_timeline(scenario, attempt)
    timeline.push({
      at_ms: current_ms,
      label: "attempt.started",
      detail: "number=" + attempt.to_string(),
    })
    let latency = response_latency(response)
    current_ms = current_ms + latency
    timeline.push({
      at_ms: current_ms,
      label: response_label(response),
      detail: response_detail(response),
    })
  }
  timeline.push({
    at_ms: max_int(current_ms, execution.finished_at_ms),
    label: "scenario.finished",
    detail: if execution_succeeded(execution) {
      "success"
    } else {
      "failure"
    },
  })
  timeline
}

///|
fn response_for_timeline(
  scenario : SimulationScenario,
  attempt : Int,
) -> SimulatedResponse {
  if scenario.responses.length() == 0 {
    return simulated_failure("empty_scenario", "no response", false, 0)
  }
  scenario.responses[min_int(attempt - 1, scenario.responses.length() - 1)]
}

///|
fn response_latency(response : SimulatedResponse) -> Int {
  match response {
    SimulatedSuccess(_, latency) => latency
    SimulatedFailure(_, _, _, latency) => latency
  }
}

///|
fn response_label(response : SimulatedResponse) -> String {
  match response {
    SimulatedSuccess(_, _) => "attempt.succeeded"
    SimulatedFailure(_, _, _, _) => "attempt.failed"
  }
}

///|
fn response_detail(response : SimulatedResponse) -> String {
  match response {
    SimulatedSuccess(value, latency) =>
      "value=" + value + " latency_ms=" + latency.to_string()
    SimulatedFailure(code, _, retryable, latency) =>
      "code=" +
      code +
      " retryable=" +
      retryable.to_string() +
      " latency_ms=" +
      latency.to_string()
  }
}
