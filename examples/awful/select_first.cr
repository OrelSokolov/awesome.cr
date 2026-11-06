# SelectFirst — every element filtered, an Array allocated, one value kept.
first_bad = results.select { |r| r.error? }.first
