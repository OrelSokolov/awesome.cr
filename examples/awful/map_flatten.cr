# MapFlatten — intermediate Array allocated, then dropped.
words = lines.map(&.split).flatten
tags = posts.map(&.tags).flatten
