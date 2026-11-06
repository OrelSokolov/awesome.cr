# AggregateAfterTransform — intermediate Array allocated just to be summed.
total = invoices.map { |inv| inv.amount }.sum
