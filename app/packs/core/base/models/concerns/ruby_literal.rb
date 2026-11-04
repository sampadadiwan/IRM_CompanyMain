require "prism"

# Builds a Ruby value from source text that is a plain literal, without evaluating anything.
#
# Dashboard widget metadata is stored as a Ruby hash literal ({months: 12, ratio_names: %w[XIRR TVPI]}),
# which JSON/YAML cannot read (unquoted keys, single quotes, %w). It used to be eval'd, which let any
# user who could save a widget run code in the app process (C1 — docs/security/security_review_2026_10.md).
# This parses the text with Prism and walks the tree, accepting only:
#   hash, array, string (incl. adjacent-string concatenation and %w[]), symbol, integer, float,
#   true, false, nil
# Anything else (method calls, operators, constants, variables, interpolation, ranges, ...) raises
# RubyLiteral::NotLiteral. Nothing in the text is ever executed.
#
# Standalone on purpose (requires only "prism"), so it can be checked without booting Rails.
module RubyLiteral
  # Raised for text that is not a plain literal, or does not parse
  class NotLiteral < StandardError; end

  module_function

  # Returns the Hash the literal `src` denotes. Blank text is an empty hash (as eval of "" gave nil -> {}).
  # Raises NotLiteral if `src` does not parse, has more than one statement, contains any non-literal
  # node, or is a literal that is not a hash.
  def parse_hash(src)
    # C1-X4 — blank / whitespace-only metadata means "no settings", as before
    return {} if src.nil? || src.strip.empty?

    # Parse only: Prism builds a syntax tree, it never runs the code
    result = Prism.parse(src)
    raise NotLiteral, "not valid syntax: #{result.errors.first.message}" if result.errors.any?

    # Exactly one top-level expression; leading/trailing whitespace and comments are ignored (C1-X4)
    statements = result.value.statements.body
    raise NotLiteral, "expected a single {key: value} hash" unless statements.size == 1

    # The top-level value must be a hash literal
    node = statements.first
    raise NotLiteral, "expected a {key: value} hash, found #{describe(node)}" unless node.is_a?(Prism::HashNode)

    build(node)
  end

  # Turns one allowed node into its Ruby value; raises NotLiteral on any other node
  def build(node)
    case node
    when Prism::HashNode, Prism::KeywordHashNode
      # KeywordHashNode is a brace-less hash inside an array literal: [a: 1] == [{a: 1}]
      build_hash(node)
    when Prism::ArrayNode
      # C1-X1 — %w[a b] and %i[a b] are ArrayNodes of String/Symbol nodes, so they need no special case
      node.elements.map { |element| build(element) }
    when Prism::StringNode
      # C1-X3 — unescaped resolves \' \" \n \t exactly as the Ruby parser does; dup gives a mutable copy
      node.unescaped.dup
    when Prism::InterpolatedStringNode
      # "a" "b" (adjacent literals) parses as an interpolated string; only plain string parts are allowed
      build_concatenation(node)
    when Prism::SymbolNode
      # :sym, :"quoted sym", and the key in {key: v} / {"key": v}
      node.unescaped.to_sym
    when Prism::IntegerNode, Prism::FloatNode
      # Prism folds a leading minus into the literal (-1, -1.5); "- 1" is a method call and is refused
      node.value
    when Prism::TrueNode then true
    when Prism::FalseNode then false
    when Prism::NilNode then nil
    else
      # C1-1 / C1-2 / C1-3 — any call, operator, constant, variable, range, interpolation, ... is refused
      raise NotLiteral, "#{describe(node)} is not a plain value"
    end
  end

  # Builds a Hash from key => value pairs. Duplicate keys resolve as eval did.
  def build_hash(node)
    node.elements.each_with_object({}) do |element, hash|
      # **splat and {key:} shorthand (an implicit method call) are not plain pairs
      raise NotLiteral, "#{describe(element)} is not a plain key: value pair" unless element.is_a?(Prism::AssocNode)

      # C1-X2 — duplicate keys: last wins (the key keeps its first position, like a Ruby hash literal)
      hash[build(element.key)] = build(element.value)
    end
  end

  # Joins the parts of "a" "b" "c"; any #{...} interpolation is refused
  def build_concatenation(node)
    node.parts.map do |part|
      case part
      when Prism::StringNode then part.unescaped
      # "a" "b" "c" nests as (("a" "b") "c")
      when Prism::InterpolatedStringNode then build_concatenation(part)
      else raise NotLiteral, "#{describe(part)} is not a plain value"
      end
    end.join
  end

  # A short, user-facing description of a node for error messages: "a method call (*) at line 1, column 8"
  def describe(node)
    kind = node.type.to_s.delete_suffix("_node").tr("_", " ")
    kind = "a method call (#{node.name})" if node.is_a?(Prism::CallNode)
    "#{kind} at line #{node.location.start_line}, column #{node.location.start_column + 1}"
  end
end
