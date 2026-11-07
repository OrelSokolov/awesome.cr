# InterpIntoIo — the interpolated String is allocated before the call.
io << "user=#{user.name} id=#{user.id}"
stdout.puts "total=#{total}"
stderr.print "err=#{err.code}"
