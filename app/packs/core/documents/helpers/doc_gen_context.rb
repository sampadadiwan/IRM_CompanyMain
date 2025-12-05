# DocGenContext builds a "key map" of everything reachable from a view context.
# The map is used only for debugging / template authoring: it shows which
# dot‑notation keys are valid inside a document template.
#
# It walks through nested data structures (Hash, Array, OpenStruct, Struct,
# Draper decorators/collections and ActiveRecord-style objects via `as_json`),
# collecting every possible path in "dot.notation" form.
#
# Example usage inside a document template:
#
#   <= context.print_keys >                # => {"user.name" => nil, "funds.0.name" => nil, ...}
#   <context.all_keys:each(key)>
#     <= key >
#   <context.all_keys:endEach>
#
# Note: this class is intentionally defensive – it tracks visited containers by
# `object_id` so that self‑referential structures cannot cause infinite recursion.

class DocGenContext
  attr_accessor :context

  def initialize(context)
    @context = context
  end

  # Returns a hash of all reachable context keys mapped to `nil`.
  # This is convenient for dumping in templates, e.g.
  # `<%= context.print_keys.to_yaml %>`.
  def print_keys
    keys_to_hash(all_keys(@context))
  end

  # Recursively collect all reachable keys from the given `data`.
  #
  # @param data [Object,nil] root object to start from. Defaults to `@context`.
  # @param prefix [String,nil] current "dot.notation" prefix used while recursing.
  # @param visited [Set<Integer>] `object_id`s of containers that have already
  #   been processed, used to avoid infinite loops for cyclic graphs.
  #
  # The method is intentionally permissive: it knows about common container
  # types (Hash, Array, Draper decorators/collections, OpenStruct/Struct) and,
  # as a fallback, will call `as_json` on any other object that supports it.
  #
  # It returns an array of unique string keys, e.g.:
  #   ["user.name", "user.email", "funds.0.name"]
  def all_keys(data = nil, prefix = nil, visited = Set.new)
    # Default to the instance context the first time the method is called.
    data ||= @context
    return [] if data.nil?

    # Only mark *containers* as visited to avoid cycles.
    # Simple scalar values (String, Numeric, etc.) are not tracked since they
    # cannot introduce recursion.
    is_container =
      data.is_a?(Hash) ||
      data.is_a?(Array) ||
      (defined?(Draper::CollectionDecorator) && data.is_a?(Draper::CollectionDecorator)) ||
      (defined?(Draper::Decorator) && data.is_a?(Draper::Decorator)) ||
      data.is_a?(OpenStruct) ||
      data.is_a?(Struct)

    if is_container
      # If we've already seen this container, bail out to prevent infinite loops
      # on cyclic object graphs.
      return [] if visited.include?(data.object_id)

      visited.add(data.object_id)
    end

    keys = []

    case data
    when Hash
      # Traverse each key/value pair, building up a new prefix for nested values.
      data.each do |key, value|
        # Avoid following the self-referential `context` pointer back to this
        # object, which would otherwise produce recursion.
        next if key.to_s == 'context' && value == self

        current_key = prefix ? "#{prefix}.#{key}" : key.to_s
        if value.nil?
          # Terminal nil value – we still expose the key so that templates know
          # it exists but currently has no data.
          keys << current_key
        else
          keys.concat(all_keys(value, current_key, visited))
        end
      end
    when Array, Draper::CollectionDecorator
      # For collections we do not append an index to the prefix; instead we
      # reuse the same prefix for each element, which keeps the key list
      # focused on attribute paths rather than concrete indices.
      data.each do |item|
        keys.concat(all_keys(item, prefix, visited))
      end
    when Draper::Decorator
      # Decorators proxy to their underlying `object`.
      keys.concat(all_keys(data.object, prefix, visited))
    when OpenStruct, Struct
      data.to_h.each do |key, value|
        current_key = prefix ? "#{prefix}.#{key}" : key.to_s
        if value.nil?
          keys << current_key
        else
          keys.concat(all_keys(value, current_key, visited))
        end
      end
    else
      # Generic fallback for arbitrary objects. We try `as_json` first so that
      # ActiveRecord-style models can be traversed as hashes.
      if data.respond_to?(:as_json)
        json_data = data.as_json
        if json_data.is_a?(Hash) && json_data != data
          keys.concat(all_keys(json_data, prefix, visited))
        elsif prefix
          # If `as_json` does not yield a traversable hash but we have a prefix,
          # treat this as a terminal leaf and record the prefix itself.
          keys << prefix
        end
      elsif prefix
        # Non-traversable, non-`as_json` object: record the prefix as a leaf.
        keys << prefix
      end
    end

    # Ensure we never return duplicates, even if the same path is discovered via
    # multiple routes.
    keys.uniq
  end

  private

  # Legacy helper kept for API compatibility. Historically `print_keys` used to
  # call `to_hash`, so this method is left here as a no-op wrapper in case
  # callers still reference it.
  def to_hash(obj)
    obj
  end

  # Convert an array of key strings into a hash where each key maps to `nil`.
  # This shape is convenient for pretty-printing (e.g. as JSON or YAML) and
  # makes it clear that the values themselves are not part of the debug output.
  def keys_to_hash(keys)
    keys.index_with { |_key| nil }
  end
end
