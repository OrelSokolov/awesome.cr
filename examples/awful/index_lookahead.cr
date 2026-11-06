# IndexLookahead — i + 1 runs past the loop's last element.
items.size.times do |i|
  process items[i + 1]
end

(0...rows.size).each do |j|
  compare rows[j], rows[j + 1]
end
