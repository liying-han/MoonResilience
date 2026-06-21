///|
test "prometheus export includes counters and labels" {
  let snapshot : @moonresilience.MetricsSnapshot = {
    executions: 3,
    successes: 2,
    failures: 1,
    retries: 4,
    circuit_opens: 1,
    rate_limit_rejections: 2,
    bulkhead_rejections: 0,
    average_latency_ms: 15,
    max_latency_ms: 40,
    custom: [],
  }
  match
    @moonresilience.export_prometheus(snapshot, labels=[
      @moonresilience.metric_label("service", "api"),
    ]) {
    Ok(text) => {
      assert_true(
        text.contains("moonresilience_executions_total{service=\"api\"} 3"),
      )
      assert_true(text.contains("# TYPE moonresilience_retries_total counter"))
      assert_true(text.contains("moonresilience_latency_max_milliseconds"))
    }
    Err(message) => abort(message)
  }
}

///|
test "prometheus exporter rejects invalid names" {
  let snapshot = @moonresilience.metrics_snapshot(@moonresilience.new_metrics())
  match @moonresilience.export_prometheus(snapshot, prefix="bad-prefix") {
    Err(message) => assert_true(message.contains("invalid metric prefix"))
    Ok(_) => abort("expected prefix error")
  }
  match
    @moonresilience.export_prometheus(snapshot, labels=[
      @moonresilience.metric_label("bad-label", "value"),
    ]) {
    Err(message) => assert_true(message.contains("invalid label name"))
    Ok(_) => abort("expected label error")
  }
}

///|
test "prometheus exporter escapes label values" {
  let snapshot = @moonresilience.metrics_snapshot(@moonresilience.new_metrics())
  match
    @moonresilience.export_prometheus(snapshot, labels=[
      @moonresilience.metric_label("path", "a\\\"b"),
    ]) {
    Ok(text) => assert_true(text.contains("path=\"a\\\\\\\"b\""))
    Err(message) => abort(message)
  }
}

///|
test "latency export emits cumulative buckets" {
  let mut histogram = @moonresilience.new_latency_histogram([10, 50])
  histogram = @moonresilience.latency_observe(histogram, 5)
  histogram = @moonresilience.latency_observe(histogram, 20)
  histogram = @moonresilience.latency_observe(histogram, 100)
  match
    @moonresilience.export_latency_prometheus(
      @moonresilience.latency_snapshot(histogram),
    ) {
    Ok(text) => {
      assert_true(text.contains("latency_bucket{le=\"10\"} 1"))
      assert_true(text.contains("latency_bucket{le=\"50\"} 2"))
      assert_true(text.contains("latency_bucket{le=\"+Inf\"} 3"))
    }
    Err(message) => abort(message)
  }
}
