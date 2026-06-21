///|
fn main {
  println("MoonResilience deterministic demo")
  println("=================================")
  match demo_chain() {
    Err(message) => println("configuration error: " + message)
    Ok(chain) => {
      run_recovery_demo(chain)
      println("")
      run_rejection_demo()
    }
  }
}

///|
fn demo_chain() -> Result[@moonresilience.PolicyChain, String] {
  let text = "retry.max_attempts=4\n" +
    "retry.max_elapsed_ms=5000\n" +
    "retry.backoff=exponential\n" +
    "retry.base_delay_ms=100\n" +
    "retry.max_delay_ms=1000\n" +
    "breaker.failure_threshold=4\n" +
    "breaker.success_threshold=1\n" +
    "breaker.open_window_ms=2000\n" +
    "limiter.kind=token_bucket\n" +
    "limiter.capacity=10\n" +
    "limiter.refill_tokens=10\n" +
    "limiter.window_ms=1000\n" +
    "bulkhead.max_concurrent=2\n" +
    "bulkhead.max_waiting=0"
  match @moonresilience.parse_config(text) {
    Err(err) => Err(@moonresilience.format_config_error(err))
    Ok(config) =>
      match @moonresilience.config_to_policy_chain(config, 0) {
        Err(err) => Err(@moonresilience.format_config_error(err))
        Ok(chain) => Ok(chain)
      }
  }
}

///|
fn run_recovery_demo(chain : @moonresilience.PolicyChain) -> Unit {
  println("[scenario] transient upstream timeout")
  let scenario = @moonresilience.simulation_scenario(
    "upstream recovers on third attempt",
    "payment.lookup",
    0,
    [
      @moonresilience.simulated_failure(
        "upstream_timeout", "first timeout", true, 40,
      ),
      @moonresilience.simulated_failure(
        "upstream_timeout", "second timeout", true, 35,
      ),
      @moonresilience.simulated_success("payment-accepted", 20),
    ],
  )
  let result = @moonresilience.simulate(chain, scenario)
  println(@moonresilience.format_simulation(result))
}

///|
fn run_rejection_demo() -> Unit {
  println("[scenario] fixed-window rate limit")
  let limiter = @moonresilience.new_fixed_window_limiter(
    @moonresilience.fixed_window_config(2, 1000),
    0,
  )
  let first = @moonresilience.fixed_window_acquire(limiter, 1, 0)
  let second = @moonresilience.fixed_window_acquire(first.limiter, 1, 1)
  let rejected = @moonresilience.fixed_window_acquire(second.limiter, 1, 2)
  println(
    "request 1: " + @moonresilience.format_rate_limit_decision(first.decision),
  )
  println(
    "request 2: " + @moonresilience.format_rate_limit_decision(second.decision),
  )
  println(
    "request 3: " +
    @moonresilience.format_rate_limit_decision(rejected.decision),
  )
}
