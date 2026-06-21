///|
pub(all) struct MetricLabel {
  name : String
  value : String
} derive(Eq, Debug)

///|
pub fn metric_label(name : String, value : String) -> MetricLabel {
  { name, value }
}

///|
pub fn export_prometheus(
  snapshot : MetricsSnapshot,
  prefix? : String = "moonresilience",
  labels? : Array[MetricLabel] = [],
) -> Result[String, String] {
  if !valid_metric_name(prefix) {
    return Err("invalid metric prefix: " + prefix)
  }
  for label in labels {
    if !valid_metric_name(label.name) {
      return Err("invalid label name: " + label.name)
    }
    if label.value.contains("\n") || label.value.contains("\r") {
      return Err("label value must not contain a newline: " + label.name)
    }
  }
  let suffix = format_labels(labels)
  let lines : Array[String] = []
  append_metric(
    lines,
    prefix,
    "executions_total",
    "Total policy executions.",
    snapshot.executions,
    suffix,
  )
  append_metric(
    lines,
    prefix,
    "successes_total",
    "Total successful executions.",
    snapshot.successes,
    suffix,
  )
  append_metric(
    lines,
    prefix,
    "failures_total",
    "Total failed executions.",
    snapshot.failures,
    suffix,
  )
  append_metric(
    lines,
    prefix,
    "retries_total",
    "Total scheduled retries.",
    snapshot.retries,
    suffix,
  )
  append_metric(
    lines,
    prefix,
    "circuit_opens_total",
    "Total circuit-open transitions.",
    snapshot.circuit_opens,
    suffix,
  )
  append_metric(
    lines,
    prefix,
    "rate_limit_rejections_total",
    "Total rate limiter rejections.",
    snapshot.rate_limit_rejections,
    suffix,
  )
  append_metric(
    lines,
    prefix,
    "bulkhead_rejections_total",
    "Total bulkhead rejections.",
    snapshot.bulkhead_rejections,
    suffix,
  )
  append_gauge(
    lines,
    prefix,
    "latency_average_milliseconds",
    "Average virtual execution latency.",
    snapshot.average_latency_ms,
    suffix,
  )
  append_gauge(
    lines,
    prefix,
    "latency_max_milliseconds",
    "Maximum virtual execution latency.",
    snapshot.max_latency_ms,
    suffix,
  )
  Ok(join_lines(lines))
}

///|
pub fn export_latency_prometheus(
  snapshot : LatencySnapshot,
  prefix? : String = "moonresilience",
  labels? : Array[MetricLabel] = [],
) -> Result[String, String] {
  if !valid_metric_name(prefix) {
    return Err("invalid metric prefix: " + prefix)
  }
  let base_labels = format_labels(labels)
  let lines : Array[String] = []
  lines.push(
    "# HELP " + prefix + "_latency_bucket Observed execution latencies.",
  )
  lines.push("# TYPE " + prefix + "_latency_bucket counter")
  let mut cumulative = 0
  for bucket in snapshot.buckets {
    cumulative = cumulative + bucket.count
    let bucket_labels = append_label_text(
      base_labels,
      "le",
      bucket.upper_bound_ms.to_string(),
    )
    lines.push(
      prefix + "_latency_bucket" + bucket_labels + " " + cumulative.to_string(),
    )
  }
  let infinity_labels = append_label_text(base_labels, "le", "+Inf")
  lines.push(
    prefix +
    "_latency_bucket" +
    infinity_labels +
    " " +
    snapshot.count.to_string(),
  )
  append_gauge(
    lines,
    prefix,
    "latency_count",
    "Total observed latencies.",
    snapshot.count,
    base_labels,
  )
  append_gauge(
    lines,
    prefix,
    "latency_max_milliseconds",
    "Maximum observed latency.",
    snapshot.max_ms,
    base_labels,
  )
  Ok(join_lines(lines))
}

///|
fn append_metric(
  lines : Array[String],
  prefix : String,
  name : String,
  help : String,
  value : Int,
  labels : String,
) -> Unit {
  let full_name = prefix + "_" + name
  lines.push("# HELP " + full_name + " " + help)
  lines.push("# TYPE " + full_name + " counter")
  lines.push(full_name + labels + " " + value.to_string())
}

///|
fn append_gauge(
  lines : Array[String],
  prefix : String,
  name : String,
  help : String,
  value : Int,
  labels : String,
) -> Unit {
  let full_name = prefix + "_" + name
  lines.push("# HELP " + full_name + " " + help)
  lines.push("# TYPE " + full_name + " gauge")
  lines.push(full_name + labels + " " + value.to_string())
}

///|
fn format_labels(labels : Array[MetricLabel]) -> String {
  if labels.length() == 0 {
    return ""
  }
  let mut text = "{"
  for index = 0; index < labels.length(); index = index + 1 {
    if index > 0 {
      text = text + ","
    }
    let label = labels[index]
    text = text + label.name + "=\"" + escape_label_value(label.value) + "\""
  }
  text + "}"
}

///|
fn append_label_text(labels : String, name : String, value : String) -> String {
  if labels.length() == 0 {
    "{" + name + "=\"" + value + "\"}"
  } else {
    labels[:labels.length() - 1].to_owned() + "," + name + "=\"" + value + "\"}"
  }
}

///|
fn escape_label_value(value : String) -> String {
  let mut output = ""
  for char in value {
    match char {
      '\\' => output = output + "\\\\"
      '"' => output = output + "\\\""
      _ => output = output + char.to_string()
    }
  }
  output
}

///|
fn valid_metric_name(name : String) -> Bool {
  if name.length() == 0 {
    return false
  }
  for index = 0; index < name.length(); index = index + 1 {
    let char = name[index]
    let allowed = (char >= 'a' && char <= 'z') ||
      (char >= 'A' && char <= 'Z') ||
      char == '_' ||
      (index > 0 && char >= '0' && char <= '9')
    if !allowed {
      return false
    }
  }
  true
}

///|
fn join_lines(lines : Array[String]) -> String {
  let mut output = ""
  for index = 0; index < lines.length(); index = index + 1 {
    output = output + lines[index] + "\n"
  }
  output
}
