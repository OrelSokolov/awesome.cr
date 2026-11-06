# FileReadLines — slurps the whole file up front.
def load_config(path)
  File.read_lines(path).each do |line|
    puts line
  end
end

def count_rows(path)
  File.read_lines(path).size # the whole file for a single number
end
