# DoubleFree — same pointer freed twice, no reassignment in between.
lib LibGeo
  fun free(ptr : Void*)
end

def close(blob : Void*)
  LibGeo.free(blob)
  puts "closed"
  LibGeo.free(blob) # double free corrupts the C heap
end
