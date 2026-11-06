# ArrayConcatInLoop — the whole Array is copied on every iteration.
acc = [] of Int32
items.each do |item|
  acc += [item]
end

log_lines = [] of String
while line = reader.gets
  log_lines = log_lines + [line] # spelled out, same full copy
end
