///|
pub(all) enum ConfigError {
  InvalidConfigLine(Int, String)
  UnknownConfigKey(Int, String)
  InvalidConfigValue(Int, String, String)
  ConfigConstraint(String, String)
} derive(Eq, Debug)

///|
pub(all) struct ResilienceConfig {
  retry_max_attempts : Int
  retry_max_elapsed_ms : Int
  retry_backoff : String
  retry_base_delay_ms : Int
  retry_max_delay_ms : Int
  breaker_failure_threshold : Int
  breaker_success_threshold : Int
  breaker_open_window_ms : Int
  breaker_half_open_max_calls : Int
  limiter_kind : String
  limiter_capacity : Int
  limiter_refill_tokens : Int
  limiter_window_ms : Int
  bulkhead_max_concurrent : Int
  bulkhead_max_waiting : Int
} derive(Eq, Debug)

///|
pub fn default_config() -> ResilienceConfig {
  {
    retry_max_attempts: 3,
    retry_max_elapsed_ms: 30000,
    retry_backoff: "exponential",
    retry_base_delay_ms: 100,
    retry_max_delay_ms: 5000,
    breaker_failure_threshold: 5,
    breaker_success_threshold: 2,
    breaker_open_window_ms: 30000,
    breaker_half_open_max_calls: 1,
    limiter_kind: "token_bucket",
    limiter_capacity: 100,
    limiter_refill_tokens: 100,
    limiter_window_ms: 1000,
    bulkhead_max_concurrent: 10,
    bulkhead_max_waiting: 20,
  }
}

///|
pub fn parse_config(input : String) -> Result[ResilienceConfig, ConfigError] {
  let mut config = default_config()
  let mut line_number = 0
  for raw in input.split("\n") {
    line_number = line_number + 1
    let line = raw.to_owned().trim().to_owned()
    if line.length() == 0 || line.has_prefix("#") {
      continue
    }
    match split_config_line(line, line_number) {
      Err(err) => return Err(err)
      Ok(pair) =>
        match apply_config_value(config, line_number, pair.0, pair.1) {
          Err(err) => return Err(err)
          Ok(next) => config = next
        }
    }
  }
  validate_config(config)
}

///|
pub fn validate_config(
  config : ResilienceConfig,
) -> Result[ResilienceConfig, ConfigError] {
  if config.retry_max_attempts <= 0 {
    return Err(ConfigConstraint("retry.max_attempts", "must be at least 1"))
  }
  if config.retry_max_elapsed_ms < 0 {
    return Err(ConfigConstraint("retry.max_elapsed_ms", "must not be negative"))
  }
  if config.retry_backoff != "fixed" &&
    config.retry_backoff != "linear" &&
    config.retry_backoff != "exponential" {
    return Err(
      ConfigConstraint("retry.backoff", "must be fixed, linear, or exponential"),
    )
  }
  if config.retry_base_delay_ms < 0 {
    return Err(ConfigConstraint("retry.base_delay_ms", "must not be negative"))
  }
  if config.retry_max_delay_ms < config.retry_base_delay_ms {
    return Err(
      ConfigConstraint(
        "retry.max_delay_ms", "must be greater than or equal to retry.base_delay_ms",
      ),
    )
  }
  if config.breaker_failure_threshold <= 0 {
    return Err(
      ConfigConstraint("breaker.failure_threshold", "must be at least 1"),
    )
  }
  if config.breaker_success_threshold <= 0 {
    return Err(
      ConfigConstraint("breaker.success_threshold", "must be at least 1"),
    )
  }
  if config.breaker_open_window_ms < 0 {
    return Err(
      ConfigConstraint("breaker.open_window_ms", "must not be negative"),
    )
  }
  if config.breaker_half_open_max_calls <= 0 {
    return Err(
      ConfigConstraint("breaker.half_open_max_calls", "must be at least 1"),
    )
  }
  if config.limiter_kind != "token_bucket" &&
    config.limiter_kind != "fixed_window" {
    return Err(
      ConfigConstraint("limiter.kind", "must be token_bucket or fixed_window"),
    )
  }
  if config.limiter_capacity <= 0 {
    return Err(ConfigConstraint("limiter.capacity", "must be at least 1"))
  }
  if config.limiter_refill_tokens <= 0 {
    return Err(ConfigConstraint("limiter.refill_tokens", "must be at least 1"))
  }
  if config.limiter_window_ms <= 0 {
    return Err(ConfigConstraint("limiter.window_ms", "must be at least 1"))
  }
  if config.bulkhead_max_concurrent <= 0 {
    return Err(
      ConfigConstraint("bulkhead.max_concurrent", "must be at least 1"),
    )
  }
  if config.bulkhead_max_waiting < 0 {
    return Err(ConfigConstraint("bulkhead.max_waiting", "must not be negative"))
  }
  Ok(config)
}

///|
pub fn config_to_policy_chain(
  config : ResilienceConfig,
  now_ms : Int,
) -> Result[PolicyChain, ConfigError] {
  match validate_config(config) {
    Err(err) => Err(err)
    Ok(valid) => {
      let backoff = match valid.retry_backoff {
        "fixed" => fixed_backoff(valid.retry_base_delay_ms)
        "linear" =>
          linear_backoff(
            valid.retry_base_delay_ms,
            valid.retry_base_delay_ms,
            valid.retry_max_delay_ms,
          )
        _ =>
          exponential_backoff(
            valid.retry_base_delay_ms,
            valid.retry_max_delay_ms,
          )
      }
      let retry = retry_policy(
        valid.retry_max_attempts,
        valid.retry_max_elapsed_ms,
        backoff,
        [],
      )
      let breaker = new_circuit_breaker(
        circuit_breaker_config(
          valid.breaker_failure_threshold,
          valid.breaker_success_threshold,
          valid.breaker_open_window_ms,
          valid.breaker_half_open_max_calls,
        ),
      )
      let limiter = if valid.limiter_kind == "fixed_window" {
        FixedWindowPolicy(
          new_fixed_window_limiter(
            fixed_window_config(valid.limiter_capacity, valid.limiter_window_ms),
            now_ms,
          ),
        )
      } else {
        TokenBucketPolicy(
          new_token_bucket(
            token_bucket_config(
              valid.limiter_capacity,
              valid.limiter_refill_tokens,
              valid.limiter_window_ms,
            ),
            now_ms,
          ),
        )
      }
      Ok(
        policy_chain(
          retry,
          breaker,
          limiter,
          new_bulkhead(
            bulkhead_config(
              valid.bulkhead_max_concurrent,
              valid.bulkhead_max_waiting,
            ),
          ),
        ),
      )
    }
  }
}

///|
pub fn format_config_error(error : ConfigError) -> String {
  match error {
    InvalidConfigLine(line, content) =>
      "line " + line.to_string() + ": expected key=value, got " + content
    UnknownConfigKey(line, key) =>
      "line " + line.to_string() + ": unknown configuration key " + key
    InvalidConfigValue(line, key, value) =>
      "line " + line.to_string() + ": invalid value for " + key + ": " + value
    ConfigConstraint(key, message) => key + ": " + message
  }
}

///|
pub fn format_config(config : ResilienceConfig) -> String {
  "retry.max_attempts=" +
  config.retry_max_attempts.to_string() +
  "\nretry.max_elapsed_ms=" +
  config.retry_max_elapsed_ms.to_string() +
  "\nretry.backoff=" +
  config.retry_backoff +
  "\nretry.base_delay_ms=" +
  config.retry_base_delay_ms.to_string() +
  "\nretry.max_delay_ms=" +
  config.retry_max_delay_ms.to_string() +
  "\nbreaker.failure_threshold=" +
  config.breaker_failure_threshold.to_string() +
  "\nbreaker.success_threshold=" +
  config.breaker_success_threshold.to_string() +
  "\nbreaker.open_window_ms=" +
  config.breaker_open_window_ms.to_string() +
  "\nbreaker.half_open_max_calls=" +
  config.breaker_half_open_max_calls.to_string() +
  "\nlimiter.kind=" +
  config.limiter_kind +
  "\nlimiter.capacity=" +
  config.limiter_capacity.to_string() +
  "\nlimiter.refill_tokens=" +
  config.limiter_refill_tokens.to_string() +
  "\nlimiter.window_ms=" +
  config.limiter_window_ms.to_string() +
  "\nbulkhead.max_concurrent=" +
  config.bulkhead_max_concurrent.to_string() +
  "\nbulkhead.max_waiting=" +
  config.bulkhead_max_waiting.to_string()
}

///|
fn split_config_line(
  line : String,
  line_number : Int,
) -> Result[(String, String), ConfigError] {
  let parts : Array[String] = []
  for part in line.split("=") {
    parts.push(part.to_owned())
  }
  if parts.length() != 2 {
    return Err(InvalidConfigLine(line_number, line))
  }
  let key = parts[0].trim().to_owned()
  let value = parts[1].trim().to_owned()
  if key.length() == 0 || value.length() == 0 {
    Err(InvalidConfigLine(line_number, line))
  } else {
    Ok((key, value))
  }
}

///|
fn apply_config_value(
  config : ResilienceConfig,
  line : Int,
  key : String,
  value : String,
) -> Result[ResilienceConfig, ConfigError] {
  match key {
    "retry.backoff" => Ok({ ..config, retry_backoff: value })
    "limiter.kind" => Ok({ ..config, limiter_kind: value })
    "retry.max_attempts" =>
      map_int_value(config, line, key, value, "retry.max_attempts")
    "retry.max_elapsed_ms" =>
      map_int_value(config, line, key, value, "retry.max_elapsed_ms")
    "retry.base_delay_ms" =>
      map_int_value(config, line, key, value, "retry.base_delay_ms")
    "retry.max_delay_ms" =>
      map_int_value(config, line, key, value, "retry.max_delay_ms")
    "breaker.failure_threshold" =>
      map_int_value(config, line, key, value, "breaker.failure_threshold")
    "breaker.success_threshold" =>
      map_int_value(config, line, key, value, "breaker.success_threshold")
    "breaker.open_window_ms" =>
      map_int_value(config, line, key, value, "breaker.open_window_ms")
    "breaker.half_open_max_calls" =>
      map_int_value(config, line, key, value, "breaker.half_open_max_calls")
    "limiter.capacity" =>
      map_int_value(config, line, key, value, "limiter.capacity")
    "limiter.refill_tokens" =>
      map_int_value(config, line, key, value, "limiter.refill_tokens")
    "limiter.window_ms" =>
      map_int_value(config, line, key, value, "limiter.window_ms")
    "bulkhead.max_concurrent" =>
      map_int_value(config, line, key, value, "bulkhead.max_concurrent")
    "bulkhead.max_waiting" =>
      map_int_value(config, line, key, value, "bulkhead.max_waiting")
    _ => Err(UnknownConfigKey(line, key))
  }
}

///|
fn map_int_value(
  config : ResilienceConfig,
  line : Int,
  key : String,
  value : String,
  field : String,
) -> Result[ResilienceConfig, ConfigError] {
  match parse_config_int(value) {
    None => Err(InvalidConfigValue(line, key, value))
    Some(number) =>
      Ok(
        match field {
          "retry.max_attempts" => { ..config, retry_max_attempts: number }
          "retry.max_elapsed_ms" => { ..config, retry_max_elapsed_ms: number }
          "retry.base_delay_ms" => { ..config, retry_base_delay_ms: number }
          "retry.max_delay_ms" => { ..config, retry_max_delay_ms: number }
          "breaker.failure_threshold" =>
            { ..config, breaker_failure_threshold: number }
          "breaker.success_threshold" =>
            { ..config, breaker_success_threshold: number }
          "breaker.open_window_ms" =>
            { ..config, breaker_open_window_ms: number }
          "breaker.half_open_max_calls" =>
            { ..config, breaker_half_open_max_calls: number }
          "limiter.capacity" => { ..config, limiter_capacity: number }
          "limiter.refill_tokens" => { ..config, limiter_refill_tokens: number }
          "limiter.window_ms" => { ..config, limiter_window_ms: number }
          "bulkhead.max_concurrent" =>
            { ..config, bulkhead_max_concurrent: number }
          _ => { ..config, bulkhead_max_waiting: number }
        },
      )
  }
}

///|
fn parse_config_int(value : String) -> Int? {
  if value.length() == 0 {
    return None
  }
  let mut result = 0
  let mut negative = false
  let mut digits = 0
  for index = 0; index < value.length(); index = index + 1 {
    let char = value[index]
    if index == 0 && char == '-' {
      negative = true
    } else if char >= '0' && char <= '9' {
      result = result * 10 + char.to_int() - '0'.to_int()
      digits = digits + 1
    } else {
      return None
    }
  }
  if digits == 0 {
    None
  } else if negative {
    Some(-result)
  } else {
    Some(result)
  }
}
