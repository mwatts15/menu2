require 'csv'

f = File.open("entries")
CSV.foreach(f,:col_sep => ", ", :row_sep => ";\n") do |line|
    print line
end
