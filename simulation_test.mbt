///|
test "virtual clock advances without real waiting" {
  let clock = @moonresilience.virtual_clock(100)
  let next = @moonresilience.clock_advance(clock, 50)
  let finished = @moonresilience.clock_advance_to(next, 500)
  assert_eq(finished.now_ms, 500)
  assert_eq(finished.advances, 2)
}

///|
test "virtual clock ignores backward target" {
  let clock = @moonresilience.virtual_clock(100)
  let same = @moonresilience.clock_advance_to(clock, 50)
  assert_eq(same.now_ms, 100)
  assert_eq(same.advances, 0)
}

///|
test "simulation recovers after retryable failures" {
  let scenario = @moonresilience.simulation_scenario(
    "transient database outage",
    "database.read",
    0,
    [
      @moonresilience.simulated_failure("timeout", "slow", true, 10),
      @moonresilience.simulated_failure("timeout", "slow", true, 10),
      @moonresilience.simulated_success("row", 5),
    ],
  )
  let result = @moonresilience.simulate(chain_for_test(), scenario)
  assert_true(@moonresilience.simulation_succeeded(result))
  assert_eq(result.attempts, 3)
  assert_eq(result.timeline.length(), 8)
}

///|
test "simulation stops on permanent failure" {
  let scenario = @moonresilience.simulation_scenario(
    "invalid request",
    "api.validate",
    0,
    [@moonresilience.simulated_failure("invalid", "bad", false, 2)],
  )
  let result = @moonresilience.simulate(chain_for_test(), scenario)
  assert_false(@moonresilience.simulation_succeeded(result))
  assert_eq(result.attempts, 1)
  assert_eq(
    @moonresilience.timeline_filter(result.timeline, "attempt.failed").length(),
    1,
  )
}

///|
test "empty scenario returns diagnostic failure" {
  let scenario = @moonresilience.simulation_scenario("empty", "worker", 0, [])
  let result = @moonresilience.simulate(chain_for_test(), scenario)
  match result.outcome {
    Err(RetryExhausted(code, _, _)) => assert_eq(code, "empty_scenario")
    _ => abort("expected empty scenario error")
  }
}

///|
test "repeat-last scenario can exhaust retry policy" {
  let scenario = @moonresilience.simulation_scenario(
    "persistent outage",
    "remote.call",
    0,
    [@moonresilience.simulated_failure("down", "offline", true, 1)],
    repeat_last=true,
  )
  let result = @moonresilience.simulate(chain_for_test(), scenario)
  assert_eq(result.attempts, 3)
  match result.outcome {
    Err(RetryExhausted(code, _, attempts)) => {
      assert_eq(code, "down")
      assert_eq(attempts, 3)
    }
    _ => abort("expected exhausted retries")
  }
}

///|
test "multiple scenarios preserve policy state" {
  let scenarios = [
    @moonresilience.simulation_scenario("first", "op-1", 0, [
      @moonresilience.simulated_success("one", 1),
    ]),
    @moonresilience.simulation_scenario("second", "op-2", 1, [
      @moonresilience.simulated_success("two", 1),
    ]),
  ]
  let results = @moonresilience.run_scenarios(chain_for_test(), scenarios)
  assert_eq(results.length(), 2)
  match results[1].chain.rate_limit {
    TokenBucketPolicy(bucket) => assert_eq(bucket.total_granted, 2)
    _ => abort("expected token bucket")
  }
}

///|
test "simulation summary aggregates outcomes" {
  let scenarios = [
    @moonresilience.simulation_scenario("ok", "op-1", 0, [
      @moonresilience.simulated_success("one", 1),
    ]),
    @moonresilience.simulation_scenario("bad", "op-2", 1, [
      @moonresilience.simulated_failure("bad", "bad", false, 1),
    ]),
  ]
  let summary = @moonresilience.simulation_summary(
    @moonresilience.run_scenarios(chain_for_test(), scenarios),
  )
  assert_true(summary.contains("scenarios=2 succeeded=1 failed=1"))
}

///|
test "formatted simulation includes timeline and metrics" {
  let scenario = @moonresilience.simulation_scenario("simple", "worker", 10, [
    @moonresilience.simulated_success("ok", 5),
  ])
  let text = @moonresilience.format_simulation(
    @moonresilience.simulate(chain_for_test(), scenario),
  )
  assert_true(text.contains("scenario=simple status=success value=ok"))
  assert_true(text.contains("scenario.started"))
  assert_true(text.contains("metrics executions=1"))
}
