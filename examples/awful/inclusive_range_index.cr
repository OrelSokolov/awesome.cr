# InclusiveRangeIndex — an inclusive range over size reaches index == size.
(0..items.size).each do |i|
  process items[i]
end

1.upto(rows.size) do |j|
  render rows[j]
end
