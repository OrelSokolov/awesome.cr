# CliStdoutEpipe — the stdout reader walked away, the process died.
puts "report line 1"
puts "report line 2"
STDOUT << "done\n"
