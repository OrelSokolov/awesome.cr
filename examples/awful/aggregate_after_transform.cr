# AggregateAfterTransform — intermediate Arrays allocated just to be
# aggregated away (sum / size / empty? on a map).
total = invoices.map { |inv| inv.amount }.sum
count = invoices.map { |inv| inv.amount }.size
empty = invoices.map { |inv| inv.amount }.empty?
