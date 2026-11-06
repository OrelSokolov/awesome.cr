# SelectCompareZero — filtered Array built just to be compared with zero.
return if items.select { |item| item.invalid? }.size == 0
