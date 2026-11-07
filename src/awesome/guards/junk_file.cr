# JunkFile — a file stuffed with types instead of one type per file.
#
# Two layout rules, both hard:
#
#   * one class per file — a second class in the same file makes it a
#     junk file: nothing in the file has a single subject, and the
#     file name can't say what's inside. A class reopened in the same
#     file is still one class; a class plus its single nested class is
#     fine too (the nesting rule below owns that).
#   * at most one nested module per module and one nested class per
#     class — more means the inner types have earned their own files
#     (folders map to namespaces in Crystal: shop/catalog.cr declares
#     `module Shop; module Catalog`).
#
# This is not a style nit: a junk file is where navigation and merges
# go to die, and no threshold tunes it away. Writing code like this is
# forbidden for everyone.
#
# Structs are skipped entirely (data, not classes — same call as
# GodClass and UtilityClass) and act as transparent containers: a
# class declared inside one still counts for its file.
class Awesome::Guards::JunkFile < Awesome::Guard
  KIND              = "code"
  LEVEL             = "vibecoder" # layout rot, not a style nit
  SEVERITY          = "warning"   # a real problem, not a taste disagreement
  SHORT_DESCRIPTION = <<-TEXT
    Checks for junk files: more than one class in a file, a module
    nesting more than one module, or a class nesting more than one
    class. One class per file, one nested module per module, one
    nested class per class — anything more belongs in its own file
    (folders map to namespaces in Crystal). Structs are skipped.
  TEXT

  GOOD_EXAMPLE = <<-CODE
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
  CODE

  BAD_EXAMPLE = <<-CODE
    class User; end
    class Order; end      # a second class — the file is a junk file

    module Shop
      module Catalog; end
      module Billing; end # a second nested module — into folders
    end
  CODE

  def test(source : Awesome::Source, config : Awesome::GuardConfig) : Array(Awesome::Issue)
    issues = [] of Awesome::Issue
    visitor = Visitor.new(source, issues)
    source.ast.try &.accept(visitor)
    visitor.finish
    issues
  end

  # Walks the type tree of one file: collects the file's class roots
  # (outermost classes — a class nested in a class belongs to its
  # outer class, not to the file's count) and counts each container's
  # direct nested modules and classes. A root reopened in the same
  # file merges by name.
  private class Visitor < Crystal::Visitor
    @stack = [] of Container # type defs currently open, innermost last
    @all = [] of Container   # every type def entered, for the verdicts
    @class_depth = 0         # enclosing non-struct ClassDefs
    # the file's class roots as {qualified name, display, location} —
    # qualified name merges reopenings, the rest feeds the report
    @roots = [] of {String, String, Crystal::Location?}

    def initialize(@source : Awesome::Source, @issues : Array(Awesome::Issue))
    end

    def visit(node : Crystal::ClassDef)
      if node.struct?
        # transparent: children are attributed to it, but it is
        # neither counted as a class nor ever checked
        enter(Container.new(node, :struct))
      else
        if @class_depth.zero?
          name = node.name.to_s
          @roots << {name, name.split("::").last, node.location} unless @roots.any? { |root| root[0] == name }
        else
          @stack.last?.try(&.bump_class(display(node)))
        end
        enter(Container.new(node, :class))
        @class_depth += 1
      end
      true
    end

    def end_visit(node : Crystal::ClassDef)
      @stack.pop
      unless node.struct?
        @class_depth -= 1
      end
    end

    def visit(node : Crystal::ModuleDef)
      @stack.last?.try(&.bump_module(display(node)))
      enter(Container.new(node, :module))
      true
    end

    def end_visit(node : Crystal::ModuleDef)
      @stack.pop
    end

    def visit(node : Crystal::ASTNode)
      true
    end

    # Reports the per-container and per-file verdicts. Called by `test`
    # after the walk — Crystal::Visitor has no end-of-file hook.
    def finish : Nil
      @all.each do |container|
        case container
        when .module?
          next unless container.modules > 1
          add_issue(container.location, "guards.JunkFile.nested_modules",
            name: container.display, count: container.modules,
            names: container.module_names.join(", "))
        when .class?
          next unless container.classes > 1
          add_issue(container.location, "guards.JunkFile.nested_classes",
            name: container.display, count: container.classes,
            names: container.class_names.join(", "))
        end
      end

      return unless @roots.size > 1

      # where the junk starts: the first class beyond the one allowed
      names = @roots.map { |root| root[1] }.uniq.join(", ")
      add_issue(@roots[1][2], "guards.JunkFile.classes",
        count: @roots.size, names: names)
    end

    private def enter(container : Container) : Nil
      @stack << container
      @all << container
    end

    private def display(node : Crystal::ClassDef | Crystal::ModuleDef) : String
      node.name.to_s.split("::").last
    end

    private def add_issue(location : Crystal::Location?, key : String, **args) : Nil
      line = location.try(&.line_number) || 0
      @issues << Awesome::Issue.new(
        @source.path,
        "JunkFile",
        Awesome::I18n.t(key, **args),
        location,
        @source.excerpt_at(line)
      )
    end

    # One entered type def: its kind, where it starts, and the direct
    # nested types counted inside it. Struct containers take bumps
    # (children are attributed to them) but are never checked.
    private class Container
      getter kind : Symbol
      getter display : String
      getter location : Crystal::Location?
      getter classes = 0
      getter modules = 0
      getter class_names = [] of String
      getter module_names = [] of String

      def initialize(node : Crystal::ClassDef | Crystal::ModuleDef, @kind)
        @display = node.name.to_s.split("::").last
        @location = node.location
      end

      def module? : Bool
        @kind == :module
      end

      def class? : Bool
        @kind == :class
      end

      def bump_class(name : String) : Nil
        @classes += 1
        @class_names << name
      end

      def bump_module(name : String) : Nil
        @modules += 1
        @module_names << name
      end
    end
  end
end

Awesome::Guard.registered << Awesome::Guards::JunkFile
