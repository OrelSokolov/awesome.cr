# HardcodedDependency — a class bypassing an abstraction it itself uses.
# The bad snippet for `awesome doc` and examples/awful: Store already
# has two implementations, Reporter declares it works with the
# abstraction (`@store : Store`) and then news up a concrete sibling in
# #rebuild — the seam is declared in the signature and welded shut one
# line below.

class Store
  def warm; end
end

class MemoryStore < Store
  def warm; end
end

class RedisStore < Store
  def warm; end
end

class Reporter
  def initialize(@store : Store)
  end

  def rebuild
    cache = MemoryStore.new # hardcoded — bypasses the Store seam
    cache.warm
  end
end
