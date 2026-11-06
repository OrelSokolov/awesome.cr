# FileReadLines — slurps the whole file up front.
def load_config(path)
  File.read_lines(path).each do |line|
    puts line
  end
end
