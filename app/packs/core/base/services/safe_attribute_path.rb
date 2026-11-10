# Reads a dotted attribute path that a user stored, e.g. a grid column key ("investor.custom_fields.sector") or a
# custom notification's PDF password field ("investor_kyc.PAN"), without letting the string choose an arbitrary
# method.
#
# Why (OWASP review 2026-11, C4 and C5): both places resolved the path with
#   path.split(".").inject(record) { |obj, name| obj.send(name) }
# so a stored "class.delete_all" deleted every tenant's rows of that table, "class.last.PAN" printed another
# firm's data, and `send` reached private Kernel methods too (exit, sleep, fork).
#
# The rules, applied to every segment:
#   - a plain reader name: word characters, optionally ending in "?" (SEGMENT); never "!" or "=" methods.
#     Unlike TemplateDecorator::PLAIN_READER_NAME it may start with a digit: six production custom fields do
#     ("1_pan_attach"), reached as portfolio_company.custom_fields.1_pan_attach. No Ruby method starts with a
#     digit, so only the custom fields proxy can answer such a name
#   - not a persistence verb (TemplateDecorator::WRITER_NAME: destroy, delete, save, update, touch, create, ...)
#   - not a hop to the class or to every row of a table (REFUSED_NAMES: class, klass, unscoped, all, ...)
#   - never called on a class or module, whatever its name (no class-level calls at all)
#   - public methods only (public_send)
#
# Checked against production data on 2026-11-09: all 308 code-defined grid column keys, all 281 stored grid
# preferences and the one stored attachment_password ("investor_kyc.PAN") pass, so no working column or
# password is refused.
#
# Not used: ActiveRecord's while_preventing_writes. Some readers create their record on first read
# (WithFolder#document_folder), and refusing those writes would blank cells that work today.
module SafeAttributePath
  # Hops from a record (or a relation) to its class, or that drop a relation's scope and reach every row of the
  # table. Shared with document templates (config/initializers/sablon_safe_lookup.rb). An ActiveRecord::Relation
  # forwards class methods, so `investor.capital_commitments.unscoped` was every firm's commitments.
  CLASS_HOP_NAMES = %w[
    class klass singleton_class superclass base_class unscoped default_scoped
    connection connection_pool descendants subclasses
    instance_variables instance_values methods public_methods private_methods singleton_methods binding method
  ].to_set.freeze

  # Everything above, plus names a grid column or PDF password never needs: Ruby plumbing (then, tap, display…),
  # side effects that are not persistence verbs (clear, purge…), and a whole-table hop (all) and the class (model).
  # Checked: no production grid key or attachment_password uses any of them.
  REFUSED_NAMES = (CLASS_HOP_NAMES + %w[
    model all itself then tap dup clone freeze object_id display
    clear purge purge_later detach discard undiscard restore really_destroy
  ]).freeze

  # One segment: word characters (a leading digit allowed, see above), optionally ending in "?"
  SEGMENT = /\A[A-Za-z0-9_]+\??\z/

  # The segment after which a name is a custom field key (WithCustomField#custom_fields → CustomFieldsProxy)
  CUSTOM_FIELDS = "custom_fields".freeze

  # Raised by #segments! for a path that breaks a rule
  class Refused < ArgumentError; end

  module_function

  # @param path [String] e.g. "investor_kyc.PAN"
  # @return [Boolean] whether every segment follows the rules (used by model validations)
  def valid?(path)
    segments!(path)
    true
  rescue Refused
    false
  end

  # @param path [String]
  # @return [Array<String>] the segments, checked
  # @raise [Refused] naming the first segment that breaks a rule
  def segments!(path)
    segments = path.to_s.strip.split(".", -1)
    raise Refused, "empty attribute path" if segments.empty?

    segments.each_with_index do |name, i|
      # Shape: a plain reader, never "!", "=", spaces or operators
      raise Refused, "#{name.inspect} is not a plain reader name" unless name.match?(SEGMENT)
      # A custom field name ("investor.custom_fields.update_only") is a key looked up in json_fields by #read!, not
      # a method, so the method-name rules below do not apply to it (production has fields named "class" and
      # "update_only")
      next if i.positive? && segments[i - 1] == CUSTOM_FIELDS
      # Persistence verbs (delete_all, destroy, update_columns, ...)
      raise Refused, "#{name.inspect} is a write method" if name.match?(TemplateDecorator::WRITER_NAME)
      # Hops to the class / table / internals
      raise Refused, "#{name.inspect} is not allowed in an attribute path" if REFUSED_NAMES.include?(name)
    end
    segments
  end

  # Reads the path on record. Nil-safe at every hop, like the code it replaces (`object&.send(method)`).
  # @param record [Object] the starting object (a model or its decorator)
  # @param path [String]
  # @return [Object, nil] the value
  # @raise [Refused] when the path, or a hop onto a class, breaks a rule
  def read!(record, path)
    segments!(path).inject(record) do |object, name|
      # Nil part-way, e.g. a commitment without an investor_kyc: nil, as before
      break nil if object.nil?
      # A reader that returned a class (or a module) is never called on
      raise Refused, "#{name.inspect} would be called on #{object.inspect}" if object.is_a?(Module)
      # A custom field: looked up by name in the record's json_fields, never called as a method
      next object[name] if object.is_a?(CustomFieldsProxy)

      object.public_send(name)
    end
  end

  # As #read!, but a refused path reads as nil and is logged, so one bad stored key blanks one cell instead of
  # failing the whole page.
  # @param context [String] where the path came from, for the log line
  def read(record, path, context: nil)
    read!(record, path)
  rescue Refused => e
    Rails.logger.warn("[safe_attribute_path] refused #{context || 'path'} #{path.to_s.truncate(200).inspect}: #{e.message}")
    nil
  end
end
