class ContextSchemaBuilder
  # This utility explores a Sablon context Hash and generates a schema for an LLM.

  def initialize(context)
    @context = context
    @schema = {}
  end

  def build
    @context.each do |key, value|
      @schema[key] = explore_object(value)
    end
    @schema
  end

  private

  def explore_object(obj)
    case obj
    when Hash
      obj.transform_values { |v| explore_object(v) }
    when Array
      obj.first ? [explore_object(obj.first)] : []
    when ActiveRecord::Base, ->(o) { o.respond_to?(:object) }
      extract_public_attributes(obj)
    else
      obj.class.name
    end
  end

  def extract_public_attributes(obj)
    # If it's a decorator, we want both decorator methods and underlying object attributes/methods
    model = obj.respond_to?(:object) ? obj.object : obj

    attrs = {}

    # 1. Get database attributes if it's an ActiveRecord model
    if model.respond_to?(:attribute_names)
      model.attribute_names.each do |attr|
        attrs[attr] = model.column_for_attribute(attr).type.to_s
      end
    end

    # 2. Get public methods that might be relevant for templates
    # We exclude common Object/ActiveRecord methods to keep the schema clean
    excluded_methods = Object.public_instance_methods + ActiveRecord::Base.public_instance_methods
    excluded_methods += %i[object model] # Common decorator methods

    # Get methods from the decorator (if any) and the model
    all_methods = obj.public_methods(false)
    all_methods += model.public_methods(false) if model != obj

    all_methods.uniq.each do |method|
      next if excluded_methods.include?(method)
      next if method.to_s.end_with?('=') # Skip setters
      next if attrs.key?(method.to_s)    # Skip if already added as attribute

      attrs[method.to_s] = "method"
    end

    attrs
  end
end
