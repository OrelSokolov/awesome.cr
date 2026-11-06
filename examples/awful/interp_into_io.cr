# InterpIntoIo — the interpolated String is allocated before << runs.
io << "user=#{user.name} id=#{user.id}"
