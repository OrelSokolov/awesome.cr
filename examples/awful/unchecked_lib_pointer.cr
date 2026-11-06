# UncheckedLibPointer — C funs returning T* can return NULL.
lib LibGeo
  fun find(id : Int32) : Float64*
  fun origin : Float64*
end

def direct(id)
  LibGeo.find(id).value # chained: deref right on the NULL-able result
end

def stored(id)
  point = LibGeo.find(id)
  point.value # stored: no null check between assignment and deref
end

def fresh(id)
  point = LibGeo.origin
  point = LibGeo.find(id) # reassigned from the lib again — still unchecked
  point.value
end
