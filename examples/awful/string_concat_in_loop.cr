# StringConcatInLoop — fresh String allocation every iteration.
report = ""
rows.each do |row|
  report += "#{row}\n"
end

body = ""
while line = reader.gets
  body = body + "#{line}\n" # spelled out, same reallocation
end
