///|
test "latency histogram normalizes boundaries" {
  let histogram = @moonresilience.new_latency_histogram([100, 10, 50, 10, -1])
  assert_eq(histogram.buckets.length(), 4)
  assert_eq(histogram.buckets[0].upper_bound_ms, 0)
  assert_eq(histogram.buckets[1].upper_bound_ms, 10)
  assert_eq(histogram.buckets[3].upper_bound_ms, 100)
}

///|
test "latency histogram places one observation in one bucket" {
  let histogram = @moonresilience.latency_observe(
    @moonresilience.new_latency_histogram([10, 50, 100]),
    42,
  )
  assert_eq(histogram.buckets[0].count, 0)
  assert_eq(histogram.buckets[1].count, 1)
  assert_eq(histogram.buckets[2].count, 0)
}

///|
test "latency histogram tracks overflow" {
  let histogram = @moonresilience.latency_observe(
    @moonresilience.new_latency_histogram([10, 50]),
    100,
  )
  assert_eq(histogram.overflow_count, 1)
  assert_eq(@moonresilience.latency_percentile(histogram, 99), 100)
}

///|
test "latency snapshot calculates percentiles" {
  let mut histogram = @moonresilience.new_latency_histogram([10, 25, 50, 100])
  for value in [5, 10, 20, 30, 40, 60, 80, 90, 100, 120] {
    histogram = @moonresilience.latency_observe(histogram, value)
  }
  let snapshot = @moonresilience.latency_snapshot(histogram)
  assert_eq(snapshot.count, 10)
  assert_eq(snapshot.average_ms, 55)
  assert_eq(snapshot.p50_ms, 50)
  assert_eq(snapshot.p90_ms, 100)
  assert_eq(snapshot.p99_ms, 120)
}

///|
test "latency merge combines compatible histograms" {
  let left = @moonresilience.latency_observe(
    @moonresilience.new_latency_histogram([10, 100]),
    5,
  )
  let right = @moonresilience.latency_observe(
    @moonresilience.new_latency_histogram([10, 100]),
    50,
  )
  match @moonresilience.latency_merge(left, right) {
    Ok(merged) => {
      assert_eq(merged.total_count, 2)
      assert_eq(merged.total_ms, 55)
      assert_eq(merged.min_ms, 5)
      assert_eq(merged.max_ms, 50)
    }
    Err(message) => abort(message)
  }
}

///|
test "latency merge rejects different boundaries" {
  match
    @moonresilience.latency_merge(
      @moonresilience.new_latency_histogram([10]),
      @moonresilience.new_latency_histogram([20]),
    ) {
    Err(message) => assert_true(message.contains("different bucket"))
    Ok(_) => abort("expected incompatible histograms")
  }
}

///|
test "batch runs requests and preserves chain state" {
  let requests = [
    @moonresilience.batch_request(
      "one",
      @moonresilience.simulation_scenario("one", "batch-1", 0, [
        @moonresilience.simulated_success("ok", 1),
      ]),
    ),
    @moonresilience.batch_request(
      "two",
      @moonresilience.simulation_scenario("two", "batch-2", 1, [
        @moonresilience.simulated_success("ok", 1),
      ]),
    ),
  ]
  let batch = @moonresilience.run_batch(chain_for_test(), requests)
  assert_eq(batch.items.length(), 2)
  match batch.final_chain.rate_limit {
    TokenBucketPolicy(bucket) => assert_eq(bucket.total_granted, 2)
    _ => abort("expected token bucket")
  }
}

///|
test "batch can stop after first failure" {
  let requests = [
    @moonresilience.batch_request(
      "bad",
      @moonresilience.simulation_scenario("bad", "batch-bad", 0, [
        @moonresilience.simulated_failure("bad", "bad", false, 1),
      ]),
    ),
    @moonresilience.batch_request(
      "unreached",
      @moonresilience.simulation_scenario("unreached", "batch-next", 1, [
        @moonresilience.simulated_success("ok", 1),
      ]),
    ),
  ]
  let batch = @moonresilience.run_batch(
    chain_for_test(),
    requests,
    stop_on_failure=true,
  )
  assert_true(batch.stopped_early)
  assert_eq(batch.items.length(), 1)
  assert_eq(@moonresilience.batch_failures(batch).length(), 1)
}

///|
test "batch summary and lookup expose results" {
  let request = @moonresilience.batch_request(
    "lookup",
    @moonresilience.simulation_scenario("lookup", "batch-lookup", 0, [
      @moonresilience.simulated_success("ok", 5),
    ]),
  )
  let batch = @moonresilience.run_batch(chain_for_test(), [request])
  let summary = @moonresilience.batch_summary(batch)
  assert_eq(summary.total, 1)
  assert_eq(summary.succeeded, 1)
  assert_true(
    @moonresilience.format_batch_summary(summary).contains(
      "total=1 succeeded=1 failed=0",
    ),
  )
  match @moonresilience.batch_find(batch, "lookup") {
    Some(result) => assert_true(@moonresilience.simulation_succeeded(result))
    None => abort("expected batch result")
  }
}
