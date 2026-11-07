# StoredLibPointer — a raw C pointer stored in a field, contract unknown.
lib LibEngine
  fun create : Void*
end

class Context
  def initialize
    @ctx = LibEngine.create # borrow or own? nothing here says which
  end
end

SHARED = LibEngine.create # same question in a constant
