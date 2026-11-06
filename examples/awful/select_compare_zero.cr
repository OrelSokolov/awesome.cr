# SelectCompareZero — filtered Array built just to be compared with zero.
return if items.select { |item| item.invalid? }.size == 0
proceed if items.select { |item| item.urgent? }.size > 0
stop if items.select { |item| item.broken? }.empty?
