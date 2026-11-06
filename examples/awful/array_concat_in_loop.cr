# ArrayConcatInLoop — the whole Array is copied on every iteration.
acc = [] of Int32
items.each do |item|
  acc += [item]
end
