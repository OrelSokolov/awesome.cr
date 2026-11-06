# TimesIndex — index machinery and bounds checks where each would do.
items.size.times do |i|
  process items[i]
end

rows.size.times do |j|
  render rows[j]
end
