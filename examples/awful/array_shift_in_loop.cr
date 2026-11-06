# ArrayShiftInLoop — O(n) memmove per call, O(n²) for the loop.
queue = ["a", "b", "c"]
while item = queue.shift?
  puts item
end
