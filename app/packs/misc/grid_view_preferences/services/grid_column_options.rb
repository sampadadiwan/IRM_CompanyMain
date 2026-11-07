# The columns a firm may add to a record type's grid: the model's standard and additional columns, the columns
# (standard and custom fields) of its related records, then the model's own custom fields.
#
# One list for Configure Grids (#flat, unchanged from the inline code it replaced) and the columns side panel
# (#call, grouped for the "Add a column" select, and #allowed_key? for the save's allowlist).
# openspec/changes/grid-columns-inline-settings — design D5, D7; worked examples H2, E10, X4
class GridColumnOptions
  CUSTOM_FIELDS_GROUP = "Custom fields".freeze

  # @param model_class [Class] e.g. Investor, CapitalCommitment (must define STANDARD_COLUMNS)
  # @param entity_id [Integer] the firm whose custom fields are offered
  def initialize(model_class, entity_id)
    @model_class = model_class
    @entity_id = entity_id
  end

  # Ordered groups of addable columns, labels as Configure Grids builds them (related ones prefixed
  # "Investor.") and keys as stored in grid_view_preferences.key.
  # @return [Hash{String => Hash{String => String}}] e.g. { "Investor" => { "Name" => "investor_name" }, ... }
  def call
    @call ||= build_groups
  end

  # The flat { label => key } list Configure Grids shows, labels without their "; css" part — same entries and
  # order as before the extraction (the related groups sit between the model's own columns and its custom fields)
  def flat
    call.values.reduce({}) { |all, group| all.merge(group) }.transform_keys { |k| k.split(";").first.strip }
  end

  # X4 — a key the panel may add: one of the offered keys, compared without any "; css" suffix
  def allowed_key?(key)
    clean = self.class.clean(key)
    return false if clean.blank?

    # Every offered key, cleaned once
    @allowed_keys ||= call.values.flat_map(&:values).to_set { |value| self.class.clean(value) }
    @allowed_keys.include?(clean)
  end

  # "committed_amount; text-end" → "committed_amount"
  def self.clean(key)
    key.to_s.split(";").first.to_s.strip
  end

  private

  def build_groups
    groups = {}
    # The model's own standard columns, plus its ADDITIONAL_COLUMNS when defined, plus GRID_COLUMNS — the
    # decorator-backed cells (name links, badges) of a list, offered here but never to the report builder, which
    # reads STANDARD/ADDITIONAL as queryable columns (openspec/changes/grid-columns-inline-settings — D21)
    own = @model_class::STANDARD_COLUMNS
    own = own.merge(@model_class::ADDITIONAL_COLUMNS) if @model_class.const_defined?(:ADDITIONAL_COLUMNS)
    own = own.merge(@model_class::GRID_COLUMNS) if @model_class.const_defined?(:GRID_COLUMNS)
    groups[@model_class.model_name.human] = own

    # The related classes whose columns are offered too (e.g. a commitment's investor), keyed by relationship
    add_classes = if @model_class.const_defined?(:ADDITIONAL_COLUMNS_FROM)
                    # to_s: Kpi lists its relationships as symbols, which have no #humanize
                    @model_class::ADDITIONAL_COLUMNS_FROM.map(&:to_s).index_with { |rel| @model_class.reflect_on_association(rel).klass }
                  else
                    {}
                  end
    # Custom field names for the model and every related class, loaded together (one query for the form types,
    # one for their fields)
    custom_names = custom_field_names([@model_class, *add_classes.values])

    add_classes.each do |relationship, add_class|
      # The related class's standard columns, labels and keys prefixed with the relationship
      related = add_class::STANDARD_COLUMNS.transform_keys { |key| "#{relationship.humanize}.#{key}" }
                                           .transform_values { |value| "#{relationship}.#{value}" }
      # ...then its custom fields
      names = custom_names[add_class.to_s.downcase]
      related = related.merge(names.to_h { |name| ["#{relationship.humanize}.#{name.humanize}", "#{relationship}.custom_fields.#{name}"] }) if names
      groups[relationship.humanize] = related
    end

    # Then the model's own custom fields
    names = custom_names[@model_class.to_s.downcase]
    groups[CUSTOM_FIELDS_GROUP] = names.to_h { |name| [name.humanize, "custom_fields.#{name}"] } if names
    groups
  end

  # Grid-selectable custom field names per class name, for the firm, in one query for the form types and one
  # for their fields (moved unchanged from GridViewPreferencesController#grid_custom_field_names):
  #   - a class with no FormType is absent from the hash;
  #   - with duplicate FormTypes of one name, the lowest id wins;
  #   - fields come in position order, minus "GridColumns" fields and fields with no field_type;
  #   - names and field types compare case-insensitively, as the MySQL columns' _ci collation did.
  # @return [Hash{String => Array<String>}] keyed by the class name downcased, e.g. { "investor" => ["pan"] }
  def custom_field_names(classes)
    form_types = FormType.where(entity_id: @entity_id, name: classes.map(&:to_s))
                         .order(:id).includes(:form_custom_fields)
    form_types.each_with_object({}) do |form_type, names|
      key = form_type.name.downcase
      # Keep the first (lowest id) form type per name
      next if names.key?(key)

      names[key] = form_type.form_custom_fields
                            .reject { |f| f.field_type.nil? || f.field_type.casecmp?("GridColumns") }
                            .map { |f| f.name.to_s }
    end
  end
end
