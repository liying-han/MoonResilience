///|
pub(all) struct LatencyBucket {
  upper_bound_ms : Int
  count : Int
} derive(Eq, Debug)

///|
pub(all) struct LatencyHistogram {
  buckets : Array[LatencyBucket]
  overflow_count : Int
  total_count : Int
  total_ms : Int
  min_ms : Int
  max_ms : Int
} derive(Eq, Debug)

///|
pub(all) struct LatencySnapshot {
  count : Int
  average_ms : Int
  min_ms : Int
  max_ms : Int
  p50_ms : Int
  p90_ms : Int
  p99_ms : Int
  buckets : Array[LatencyBucket]
  overflow_count : Int
} derive(Eq, Debug)

///|
pub fn new_latency_histogram(upper_bounds_ms : Array[Int]) -> LatencyHistogram {
  let normalized = normalize_bounds(upper_bounds_ms)
  let buckets : Array[LatencyBucket] = []
  for bound in normalized {
    buckets.push({ upper_bound_ms: bound, count: 0 })
  }
  {
    buckets,
    overflow_count: 0,
    total_count: 0,
    total_ms: 0,
    min_ms: 0,
    max_ms: 0,
  }
}

///|
pub fn default_latency_histogram() -> LatencyHistogram {
  new_latency_histogram([5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000])
}

///|
pub fn latency_observe(
  histogram : LatencyHistogram,
  latency_ms : Int,
) -> LatencyHistogram {
  let value = clamp_non_negative(latency_ms)
  let buckets : Array[LatencyBucket] = []
  let mut placed = false
  for bucket in histogram.buckets {
    if !placed && value <= bucket.upper_bound_ms {
      buckets.push({ ..bucket, count: bucket.count + 1 })
      placed = true
    } else {
      buckets.push(bucket)
    }
  }
  let overflow_increment = if placed { 0 } else { 1 }
  {
    buckets,
    overflow_count: histogram.overflow_count + overflow_increment,
    total_count: histogram.total_count + 1,
    total_ms: histogram.total_ms + value,
    min_ms: if histogram.total_count == 0 {
      value
    } else {
      min_int(histogram.min_ms, value)
    },
    max_ms: max_int(histogram.max_ms, value),
  }
}

///|
pub fn latency_merge(
  left : LatencyHistogram,
  right : LatencyHistogram,
) -> Result[LatencyHistogram, String] {
  if !same_bounds(left.buckets, right.buckets) {
    return Err("latency histograms use different bucket boundaries")
  }
  let buckets : Array[LatencyBucket] = []
  for index = 0; index < left.buckets.length(); index = index + 1 {
    buckets.push({
      upper_bound_ms: left.buckets[index].upper_bound_ms,
      count: left.buckets[index].count + right.buckets[index].count,
    })
  }
  let total_count = left.total_count + right.total_count
  Ok({
    buckets,
    overflow_count: left.overflow_count + right.overflow_count,
    total_count,
    total_ms: left.total_ms + right.total_ms,
    min_ms: if left.total_count == 0 {
      right.min_ms
    } else if right.total_count == 0 {
      left.min_ms
    } else {
      min_int(left.min_ms, right.min_ms)
    },
    max_ms: max_int(left.max_ms, right.max_ms),
  })
}

///|
pub fn latency_percentile(
  histogram : LatencyHistogram,
  percentile : Int,
) -> Int {
  if histogram.total_count == 0 {
    return 0
  }
  let safe = min_int(100, max_int(1, percentile))
  let target = (histogram.total_count * safe + 99) / 100
  let mut cumulative = 0
  for bucket in histogram.buckets {
    cumulative = cumulative + bucket.count
    if cumulative >= target {
      return bucket.upper_bound_ms
    }
  }
  histogram.max_ms
}

///|
pub fn latency_snapshot(histogram : LatencyHistogram) -> LatencySnapshot {
  {
    count: histogram.total_count,
    average_ms: if histogram.total_count == 0 {
      0
    } else {
      histogram.total_ms / histogram.total_count
    },
    min_ms: histogram.min_ms,
    max_ms: histogram.max_ms,
    p50_ms: latency_percentile(histogram, 50),
    p90_ms: latency_percentile(histogram, 90),
    p99_ms: latency_percentile(histogram, 99),
    buckets: histogram.buckets.copy(),
    overflow_count: histogram.overflow_count,
  }
}

///|
pub fn format_latency_snapshot(snapshot : LatencySnapshot) -> String {
  "count=" +
  snapshot.count.to_string() +
  " average_ms=" +
  snapshot.average_ms.to_string() +
  " min_ms=" +
  snapshot.min_ms.to_string() +
  " max_ms=" +
  snapshot.max_ms.to_string() +
  " p50_ms=" +
  snapshot.p50_ms.to_string() +
  " p90_ms=" +
  snapshot.p90_ms.to_string() +
  " p99_ms=" +
  snapshot.p99_ms.to_string() +
  " overflow=" +
  snapshot.overflow_count.to_string()
}

///|
fn normalize_bounds(bounds : Array[Int]) -> Array[Int] {
  let result : Array[Int] = []
  for bound in bounds {
    let safe = clamp_non_negative(bound)
    if !contains_int(result, safe) {
      insert_sorted(result, safe)
    }
  }
  result
}

///|
fn insert_sorted(values : Array[Int], value : Int) -> Unit {
  let mut index = 0
  while index < values.length() && values[index] < value {
    index = index + 1
  }
  values.insert(index, value)
}

///|
fn contains_int(values : Array[Int], target : Int) -> Bool {
  for value in values {
    if value == target {
      return true
    }
  }
  false
}

///|
fn same_bounds(
  left : Array[LatencyBucket],
  right : Array[LatencyBucket],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for index = 0; index < left.length(); index = index + 1 {
    if left[index].upper_bound_ms != right[index].upper_bound_ms {
      return false
    }
  }
  true
}
