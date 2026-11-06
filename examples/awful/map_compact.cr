# MapCompact — the map's Array is walked a second time to drop nils.
names = users.map { |u| u.email }.compact
