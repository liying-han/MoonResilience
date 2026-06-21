///|
pub(all) struct NamedPolicy {
  name : String
  chain : PolicyChain
  description : String
} derive(Eq, Debug)

///|
pub(all) struct PolicyRegistry {
  policies : Array[NamedPolicy]
  default_name : String?
} derive(Eq, Debug)

///|
pub(all) enum RegistryError {
  EmptyPolicyName
  DuplicatePolicyName(String)
  PolicyNotFound(String)
  DefaultPolicyNotFound(String)
} derive(Eq, Debug)

///|
pub fn new_policy_registry() -> PolicyRegistry {
  { policies: [], default_name: None }
}

///|
pub fn registry_add(
  registry : PolicyRegistry,
  name : String,
  chain : PolicyChain,
  description? : String = "",
) -> Result[PolicyRegistry, RegistryError] {
  if name.length() == 0 {
    return Err(EmptyPolicyName)
  }
  if registry_contains(registry, name) {
    return Err(DuplicatePolicyName(name))
  }
  let policies = registry.policies.copy()
  policies.push({ name, chain, description })
  Ok({ ..registry, policies, })
}

///|
pub fn registry_replace(
  registry : PolicyRegistry,
  name : String,
  chain : PolicyChain,
  description? : String = "",
) -> Result[PolicyRegistry, RegistryError] {
  if !registry_contains(registry, name) {
    return Err(PolicyNotFound(name))
  }
  let policies : Array[NamedPolicy] = []
  for policy in registry.policies {
    if policy.name == name {
      policies.push({ name, chain, description })
    } else {
      policies.push(policy)
    }
  }
  Ok({ ..registry, policies, })
}

///|
pub fn registry_remove(
  registry : PolicyRegistry,
  name : String,
) -> Result[PolicyRegistry, RegistryError] {
  if !registry_contains(registry, name) {
    return Err(PolicyNotFound(name))
  }
  let policies : Array[NamedPolicy] = []
  for policy in registry.policies {
    if policy.name != name {
      policies.push(policy)
    }
  }
  let default_name = match registry.default_name {
    Some(current) => if current == name { None } else { Some(current) }
    None => None
  }
  Ok({ policies, default_name })
}

///|
pub fn registry_set_default(
  registry : PolicyRegistry,
  name : String,
) -> Result[PolicyRegistry, RegistryError] {
  if registry_contains(registry, name) {
    Ok({ ..registry, default_name: Some(name) })
  } else {
    Err(DefaultPolicyNotFound(name))
  }
}

///|
pub fn registry_find(
  registry : PolicyRegistry,
  name : String,
) -> Result[PolicyChain, RegistryError] {
  for policy in registry.policies {
    if policy.name == name {
      return Ok(policy.chain)
    }
  }
  Err(PolicyNotFound(name))
}

///|
pub fn registry_default(
  registry : PolicyRegistry,
) -> Result[PolicyChain, RegistryError] {
  match registry.default_name {
    Some(name) => registry_find(registry, name)
    None => Err(DefaultPolicyNotFound("<unset>"))
  }
}

///|
pub fn registry_contains(registry : PolicyRegistry, name : String) -> Bool {
  for policy in registry.policies {
    if policy.name == name {
      return true
    }
  }
  false
}

///|
pub fn registry_names(registry : PolicyRegistry) -> Array[String] {
  let names : Array[String] = []
  for policy in registry.policies {
    names.push(policy.name)
  }
  names
}

///|
pub fn format_registry_error(error : RegistryError) -> String {
  match error {
    EmptyPolicyName => "policy name must not be empty"
    DuplicatePolicyName(name) => "policy already exists: " + name
    PolicyNotFound(name) => "policy not found: " + name
    DefaultPolicyNotFound(name) => "default policy not found: " + name
  }
}
