# DoubleFree — same pointer freed twice, no reassignment in between.
lib LibGeo
  fun free(ptr : Void*)
end

def close(blob : Void*)
  LibGeo.free(blob)
  puts "closed"
  LibGeo.free(blob) # double free corrupts the C heap
end

def reset(cache : Void*)
  LibGeo.free(cache)
  LibGeo.free(cache) # same shape in a second block — still a double free
end
