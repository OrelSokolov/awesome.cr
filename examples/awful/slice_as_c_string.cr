# SliceAsCString — to_unsafe handed to a C-string param with no length.
lib LibCfg
  fun read(name : UInt8*) : Int32
  fun load(tag : Char*) : Int32
end

LibCfg.read(buf.to_unsafe)   # buf may be a Slice — no NUL, no length
LibCfg.load(sym.to_unsafe)   # same shape on a Char* parameter
