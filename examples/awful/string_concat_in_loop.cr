# StringConcatInLoop — fresh String allocation every iteration.
report = ""
rows.each do |row|
  report += "#{row}\n"
end
