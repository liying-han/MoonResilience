///|
pub(all) struct TokenBucketConfig {
  capacity : Int
  refill_tokens : Int
  refill_period_ms : Int
} derive(Eq, Debug)

///|
pub(all) struct TokenBucket {
  config : TokenBucketConfig
  available_tokens : Int
  last_refill_ms : Int
  total_granted : Int
  total_rejected : Int
} derive(Eq, Debug)

///|
pub(all) struct FixedWindowConfig {
  limit : Int
  window_ms : Int
} derive(Eq, Debug)

///|
pub(all) struct FixedWindowLimiter {
  config : FixedWindowConfig
  window_started_ms : Int
  used : Int
  total_granted : Int
  total_rejected : Int
} derive(Eq, Debug)

///|
pub(all) struct RateLimitDecision {
  allowed : Bool
  remaining : Int
  retry_after_ms : Int
  reason : String
} derive(Eq, Debug)

///|
pub(all) struct TokenBucketResult {
  bucket : TokenBucket
  decision : RateLimitDecision
} derive(Eq, Debug)

///|
pub(all) struct FixedWindowResult {
  limiter : FixedWindowLimiter
  decision : RateLimitDecision
} derive(Eq, Debug)

///|
pub fn token_bucket_config(
  capacity : Int,
  refill_tokens : Int,
  refill_period_ms : Int,
) -> TokenBucketConfig {
  {
    capacity: clamp_at_least_one(capacity),
    refill_tokens: clamp_at_least_one(refill_tokens),
    refill_period_ms: clamp_at_least_one(refill_period_ms),
  }
}

///|
pub fn new_token_bucket(
  config : TokenBucketConfig,
  now_ms : Int,
) -> TokenBucket {
  let safe = token_bucket_config(
    config.capacity,
    config.refill_tokens,
    config.refill_period_ms,
  )
  {
    config: safe,
    available_tokens: safe.capacity,
    last_refill_ms: clamp_non_negative(now_ms),
    total_granted: 0,
    total_rejected: 0,
  }
}

///|
pub fn token_bucket_with_tokens(
  config : TokenBucketConfig,
  tokens : Int,
  now_ms : Int,
) -> TokenBucket {
  let bucket = new_token_bucket(config, now_ms)
  {
    ..bucket,
    available_tokens: min_int(bucket.config.capacity, max_int(0, tokens)),
  }
}

///|
pub fn refill_token_bucket(bucket : TokenBucket, now_ms : Int) -> TokenBucket {
  if now_ms <= bucket.last_refill_ms {
    return bucket
  }
  let elapsed = now_ms - bucket.last_refill_ms
  let periods = elapsed / bucket.config.refill_period_ms
  if periods <= 0 {
    return bucket
  }
  let added = periods * bucket.config.refill_tokens
  {
    ..bucket,
    available_tokens: min_int(
      bucket.config.capacity,
      bucket.available_tokens + added,
    ),
    last_refill_ms: bucket.last_refill_ms +
    periods * bucket.config.refill_period_ms,
  }
}

///|
pub fn token_bucket_acquire(
  bucket : TokenBucket,
  permits : Int,
  now_ms : Int,
) -> TokenBucketResult {
  let requested = clamp_at_least_one(permits)
  let current = refill_token_bucket(bucket, now_ms)
  if requested > current.config.capacity {
    return {
      bucket: { ..current, total_rejected: current.total_rejected + 1 },
      decision: {
        allowed: false,
        remaining: current.available_tokens,
        retry_after_ms: -1,
        reason: "requested permits exceed bucket capacity",
      },
    }
  }
  if current.available_tokens >= requested {
    let remaining = current.available_tokens - requested
    {
      bucket: {
        ..current,
        available_tokens: remaining,
        total_granted: current.total_granted + requested,
      },
      decision: {
        allowed: true,
        remaining,
        retry_after_ms: 0,
        reason: "granted",
      },
    }
  } else {
    {
      bucket: { ..current, total_rejected: current.total_rejected + 1 },
      decision: {
        allowed: false,
        remaining: current.available_tokens,
        retry_after_ms: token_retry_after(current, requested, now_ms),
        reason: "insufficient tokens",
      },
    }
  }
}

///|
pub fn token_bucket_reset(bucket : TokenBucket, now_ms : Int) -> TokenBucket {
  {
    ..bucket,
    available_tokens: bucket.config.capacity,
    last_refill_ms: clamp_non_negative(now_ms),
  }
}

///|
pub fn fixed_window_config(limit : Int, window_ms : Int) -> FixedWindowConfig {
  { limit: clamp_at_least_one(limit), window_ms: clamp_at_least_one(window_ms) }
}

///|
pub fn new_fixed_window_limiter(
  config : FixedWindowConfig,
  now_ms : Int,
) -> FixedWindowLimiter {
  {
    config: fixed_window_config(config.limit, config.window_ms),
    window_started_ms: clamp_non_negative(now_ms),
    used: 0,
    total_granted: 0,
    total_rejected: 0,
  }
}

///|
pub fn roll_fixed_window(
  limiter : FixedWindowLimiter,
  now_ms : Int,
) -> FixedWindowLimiter {
  if now_ms < limiter.window_started_ms + limiter.config.window_ms {
    return limiter
  }
  let elapsed = now_ms - limiter.window_started_ms
  let windows = elapsed / limiter.config.window_ms
  {
    ..limiter,
    window_started_ms: limiter.window_started_ms +
    windows * limiter.config.window_ms,
    used: 0,
  }
}

///|
pub fn fixed_window_acquire(
  limiter : FixedWindowLimiter,
  permits : Int,
  now_ms : Int,
) -> FixedWindowResult {
  let requested = clamp_at_least_one(permits)
  let current = roll_fixed_window(limiter, now_ms)
  if requested > current.config.limit {
    return {
      limiter: { ..current, total_rejected: current.total_rejected + 1 },
      decision: {
        allowed: false,
        remaining: max_int(0, current.config.limit - current.used),
        retry_after_ms: -1,
        reason: "requested permits exceed window limit",
      },
    }
  }
  if current.used + requested <= current.config.limit {
    let used = current.used + requested
    {
      limiter: {
        ..current,
        used,
        total_granted: current.total_granted + requested,
      },
      decision: {
        allowed: true,
        remaining: current.config.limit - used,
        retry_after_ms: 0,
        reason: "granted",
      },
    }
  } else {
    {
      limiter: { ..current, total_rejected: current.total_rejected + 1 },
      decision: {
        allowed: false,
        remaining: max_int(0, current.config.limit - current.used),
        retry_after_ms: max_int(
          0,
          current.window_started_ms + current.config.window_ms - now_ms,
        ),
        reason: "fixed window limit exhausted",
      },
    }
  }
}

///|
pub fn fixed_window_reset(
  limiter : FixedWindowLimiter,
  now_ms : Int,
) -> FixedWindowLimiter {
  { ..limiter, window_started_ms: clamp_non_negative(now_ms), used: 0 }
}

///|
pub fn format_rate_limit_decision(decision : RateLimitDecision) -> String {
  if decision.allowed {
    "allowed remaining=" + decision.remaining.to_string()
  } else {
    "rejected reason=" +
    decision.reason +
    " remaining=" +
    decision.remaining.to_string() +
    " retry_after_ms=" +
    decision.retry_after_ms.to_string()
  }
}

///|
fn token_retry_after(bucket : TokenBucket, permits : Int, now_ms : Int) -> Int {
  let missing = permits - bucket.available_tokens
  let periods = (missing + bucket.config.refill_tokens - 1) /
    bucket.config.refill_tokens
  let next_refill = bucket.last_refill_ms + bucket.config.refill_period_ms
  let first_wait = max_int(0, next_refill - now_ms)
  first_wait + max_int(0, periods - 1) * bucket.config.refill_period_ms
}
