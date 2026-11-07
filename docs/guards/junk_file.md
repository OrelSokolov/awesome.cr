# JunkFile

**Checks for junk files: more than one class in a file, a module nesting more than one module, or a class nesting more than one class.**

## Why

A file with several classes has no single subject: the file name can't
say what's inside, navigation and grep get noisy, and every merge
conflict lands in the same place. The same goes for containers piled
with nested types — a module holding three modules is a folder that
grew inside a file instead of on disk.

The rules are hard, with no thresholds to tune:

- **one class per file** — a second class makes the file a junk file.
  A class reopened in the same file is still one class.
- **at most one nested module per module, one nested class per class**
  — anything more belongs in its own file (folders map to namespaces
  in Crystal: `shop/catalog.cr` declares `module Shop; module Catalog`).

This is a warning, not a style nit: layout rot is where codebase
navigation goes to die.

## Examples

Good:

```crystal
# user.cr — one class, its own file
class User
  def initialize(@name : String)
  end
end

# shop/catalog.cr — the nested module in its own file
module Shop
  module Catalog
  end
end
```

Bad:

```crystal
class User; end
class Order; end      # a second class — the file is a junk file

module Shop
  module Catalog; end
  module Billing; end # a second nested module — into folders
end
```

## What is skipped

- Structs — value types carry data, not roles (same call as GodClass
  and UtilityClass). A struct is a transparent container: a class
  declared inside one still counts for its file.
- Modules toward the per-file class count — a file may hold several
  modules; only classes make it a junk file.
- A class plus its single nested class — allowed; a second nested
  class is what fires.

## Config

```yaml
guards:
  JunkFile:
    enabled: true
```
