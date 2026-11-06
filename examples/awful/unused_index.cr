# UnusedIndex — the index is never read, plain each would do.
rows.each_with_index do |row, i|
  puts row
end
