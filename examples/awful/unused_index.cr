# UnusedIndex — the index is never read, plain each would do.
rows.each_with_index do |row, i|
  puts row
end

points.each_with_index do |point, idx|
  render point
end
