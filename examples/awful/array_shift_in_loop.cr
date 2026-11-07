# ArrayShiftInLoop — O(n) memmove per call, O(n²) for the loop.
queue = ["a", "b", "c"]
while item = queue.shift?
  process(item)
end

stack = [] of Int32
10.times do
  stack.unshift(next_id)
end
