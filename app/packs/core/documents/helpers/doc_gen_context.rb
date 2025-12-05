# This class helps in generating a context key map for document generation debugging
# It traverses nested structures including Hashes, Arrays, OpenStructs, Draper Decorators, and ActiveRecord objects
# to extract all possible keys in a dot-notated format.
# Inside the templates, you can use it as follows:
#   <= context.print_keys >
# <context.all_keys:each(key)>
#  <= key >
# <context.all_keys:endEach>

class DocGenContext
  attr_accessor :context

  def initialize(context)
    @context = context
  end

  def print_keys
    keys_to_hash(all_keys(@context))
  end

  def all_keys(data = nil, prefix = nil, visited = Set.new)
    data ||= @context
    return [] if data.nil?

    # Only mark *containers* as visited to avoid cycles
    is_container =
      data.is_a?(Hash) ||
      data.is_a?(Array) ||
      (defined?(Draper::CollectionDecorator) && data.is_a?(Draper::CollectionDecorator)) ||
      (defined?(Draper::Decorator) && data.is_a?(Draper::Decorator)) ||
      data.is_a?(OpenStruct) ||
      data.is_a?(Struct)

    if is_container
      return [] if visited.include?(data.object_id)

      visited.add(data.object_id)
    end

    keys = []

    case data
    when Hash
      data.each do |key, value|
        next if key.to_s == 'context' && value == self

        current_key = prefix ? "#{prefix}.#{key}" : key.to_s
        if value.nil?
          keys << current_key
        else
          keys.concat(all_keys(value, current_key, visited))
        end
      end
    when Array, Draper::CollectionDecorator
      data.each do |item|
        keys.concat(all_keys(item, prefix, visited))
      end
    when Draper::Decorator
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
      if data.respond_to?(:as_json)
        json_data = data.as_json
        if json_data.is_a?(Hash) && json_data != data
          keys.concat(all_keys(json_data, prefix, visited))
        elsif prefix
          keys << prefix
        end
      elsif prefix
        keys << prefix
      end
    end
    keys.uniq
  end

  private

  def to_hash(obj)
    obj
  end

  def keys_to_hash(keys)
    keys.index_with { |_key| nil }
  end
end
