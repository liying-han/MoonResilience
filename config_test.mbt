///|
test "empty config uses documented defaults" {
  match @moonresilience.parse_config("") {
    Ok(config) => {
      assert_eq(config.retry_max_attempts, 3)
      assert_eq(config.limiter_kind, "token_bucket")
      assert_eq(config.bulkhead_max_concurrent, 10)
    }
    Err(err) => abort(@moonresilience.format_config_error(err))
  }
}

///|
test "config parser accepts comments whitespace and overrides" {
  let input = "# production defaults\nretry.max_attempts = 5\nlimiter.kind=fixed_window\nbulkhead.max_waiting=0"
  match @moonresilience.parse_config(input) {
    Ok(config) => {
      assert_eq(config.retry_max_attempts, 5)
      assert_eq(config.limiter_kind, "fixed_window")
      assert_eq(config.bulkhead_max_waiting, 0)
    }
    Err(err) => abort(@moonresilience.format_config_error(err))
  }
}

///|
test "config parser reports malformed line number" {
  match @moonresilience.parse_config("retry.max_attempts=3\nnot-a-pair") {
    Err(InvalidConfigLine(line, _)) => assert_eq(line, 2)
    _ => abort("expected malformed line")
  }
}

///|
test "config parser reports unknown key" {
  match @moonresilience.parse_config("unknown.option=3") {
    Err(UnknownConfigKey(line, key)) => {
      assert_eq(line, 1)
      assert_eq(key, "unknown.option")
    }
    _ => abort("expected unknown key")
  }
}

///|
test "config parser reports non-numeric integer" {
  match @moonresilience.parse_config("retry.max_attempts=many") {
    Err(InvalidConfigValue(line, key, value)) => {
      assert_eq(line, 1)
      assert_eq(key, "retry.max_attempts")
      assert_eq(value, "many")
    }
    _ => abort("expected invalid value")
  }
}

///|
test "config validation rejects impossible retry range" {
  match
    @moonresilience.parse_config(
      "retry.base_delay_ms=1000\nretry.max_delay_ms=100",
    ) {
    Err(ConfigConstraint(key, _)) => assert_eq(key, "retry.max_delay_ms")
    _ => abort("expected retry range error")
  }
}

///|
test "config validation rejects unsupported limiter" {
  match @moonresilience.parse_config("limiter.kind=sliding_window") {
    Err(ConfigConstraint(key, message)) => {
      assert_eq(key, "limiter.kind")
      assert_true(message.contains("token_bucket"))
    }
    _ => abort("expected limiter kind error")
  }
}

///|
test "validated config builds fixed-window chain" {
  let config = match
    @moonresilience.parse_config(
      "limiter.kind=fixed_window\nlimiter.capacity=7\nlimiter.window_ms=500",
    ) {
    Ok(value) => value
    Err(err) => abort(@moonresilience.format_config_error(err))
  }
  match @moonresilience.config_to_policy_chain(config, 100) {
    Ok(chain) =>
      match chain.rate_limit {
        FixedWindowPolicy(limiter) => {
          assert_eq(limiter.config.limit, 7)
          assert_eq(limiter.window_started_ms, 100)
        }
        _ => abort("expected fixed window")
      }
    Err(err) => abort(@moonresilience.format_config_error(err))
  }
}

///|
test "formatted config can be parsed again" {
  let original = @moonresilience.default_config()
  match @moonresilience.parse_config(@moonresilience.format_config(original)) {
    Ok(parsed) => assert_true(parsed == original)
    Err(err) => abort(@moonresilience.format_config_error(err))
  }
}
