///|
pub(all) struct BatchRequest {
  id : String
  scenario : SimulationScenario
} derive(Eq, Debug)

///|
pub(all) struct BatchItemResult {
  id : String
  result : SimulationResult
} derive(Debug)

///|
pub(all) struct BatchResult {
  items : Array[BatchItemResult]
  final_chain : PolicyChain
  stopped_early : Bool
} derive(Debug)

///|
pub(all) struct BatchSummary {
  total : Int
  succeeded : Int
  failed : Int
  attempts : Int
  virtual_duration_ms : Int
  stopped_early : Bool
} derive(Eq, Debug)

///|
pub fn batch_request(
  id : String,
  scenario : SimulationScenario,
) -> BatchRequest {
  { id, scenario }
}

///|
pub fn run_batch(
  chain : PolicyChain,
  requests : Array[BatchRequest],
  stop_on_failure? : Bool = false,
) -> BatchResult {
  let items : Array[BatchItemResult] = []
  let mut current = chain
  let mut stopped_early = false
  for request in requests {
    let result = simulate(current, request.scenario)
    current = result.chain
    items.push({ id: request.id, result })
    if stop_on_failure && !simulation_succeeded(result) {
      stopped_early = true
      break
    }
  }
  { items, final_chain: current, stopped_early }
}

///|
pub fn batch_summary(batch : BatchResult) -> BatchSummary {
  let mut succeeded = 0
  let mut failed = 0
  let mut attempts = 0
  let mut duration = 0
  for item in batch.items {
    if simulation_succeeded(item.result) {
      succeeded = succeeded + 1
    } else {
      failed = failed + 1
    }
    attempts = attempts + item.result.attempts
    duration = duration + simulation_duration_ms(item.result)
  }
  {
    total: batch.items.length(),
    succeeded,
    failed,
    attempts,
    virtual_duration_ms: duration,
    stopped_early: batch.stopped_early,
  }
}

///|
pub fn batch_find(batch : BatchResult, id : String) -> SimulationResult? {
  for item in batch.items {
    if item.id == id {
      return Some(item.result)
    }
  }
  None
}

///|
pub fn batch_failures(batch : BatchResult) -> Array[BatchItemResult] {
  let failures : Array[BatchItemResult] = []
  for item in batch.items {
    if !simulation_succeeded(item.result) {
      failures.push(item)
    }
  }
  failures
}

///|
pub fn format_batch_summary(summary : BatchSummary) -> String {
  "total=" +
  summary.total.to_string() +
  " succeeded=" +
  summary.succeeded.to_string() +
  " failed=" +
  summary.failed.to_string() +
  " attempts=" +
  summary.attempts.to_string() +
  " virtual_duration_ms=" +
  summary.virtual_duration_ms.to_string() +
  " stopped_early=" +
  summary.stopped_early.to_string()
}
