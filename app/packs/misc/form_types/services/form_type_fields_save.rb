# ④ Saves the custom fields side panel opened from a record's page: applies every change — order, labels,
# Required / Read only / Internal, help text, removals, additions — to the record's form type in one transaction,
# through the Form Types nested update (so uniqueness, the field callbacks and option clean-up all apply).
# openspec/changes/grid-columns-inline-settings — design D14, D15; lld.md › Phase 3 contracts
class FormTypeFieldsSave
  MAX_FIELDS = 200
  LABEL_MAX = 254
  # The types the panel can add (others are set up on Form Types › Edit)
  NEW_FIELD_TYPES = %w[TextField NumberField DateField TextArea CheckBox Select Money].freeze
  FLAGS = %w[required read_only internal].freeze

  Result = Struct.new(:success, :errors, :form_type) do
    def success? = success
  end

  def self.call(...)
    new(...).call
  end

  # The form type a record's fields come from: its own, else the one new records of its type pick
  # (WithCustomField#setup_form_type), else a new one for its firm, created on the first save (H13, E13)
  def self.form_type_for(record)
    record.form_type ||
      record.entity.form_types.where(name: record.class.name).last ||
      FormType.new(entity: record.entity, name: record.class.name)
  end

  # @param user [User] the admin saving (already authorized by the controller)
  # @param form_type [FormType] from .form_type_for (may be unsaved)
  # @param record [ApplicationRecord, nil] the record whose page the panel was opened on (nil from a form)
  # @param fields [String] JSON array: { "id", "label", "required", "read_only", "internal", "help_text", "_destroy" }
  #   for an existing field, { "label", "field_type", "options", flags…, "help_text" } for a new one
  def initialize(user:, form_type:, record:, fields:)
    @user = user
    @form_type = form_type
    @record = record
    @raw_fields = fields
    @errors = []
  end

  def call
    items = parse_fields
    return failure if @errors.any?

    ActiveRecord::Base.transaction do
      # H13 — the firm's form type for the record type is created on the first save
      @form_type.save! if @form_type.new_record?
      # Two admins saving the same form type: one after the other
      @form_type.lock!
      apply(items)
      raise ActiveRecord::Rollback if @errors.any?

      # H13, E13 — a record with no form type is linked to the one it showed; only the link is written
      @record.update_column(:form_type_id, @form_type.id) if @record && @record.form_type_id.nil?
    end
    return failure if @errors.any?

    Result.new(success: true, errors: [], form_type: @form_type)
  rescue ActiveRecord::RecordNotUnique
    @errors << "Two fields would have the same name"
    failure
  end

  private

  def failure
    Result.new(success: false, errors: @errors, form_type: @form_type)
  end

  def parse_fields
    items = JSON.parse(@raw_fields.to_s)
    raise JSON::ParserError unless items.is_a?(Array) && items.size <= MAX_FIELDS && items.all?(Hash)

    items
  rescue JSON::ParserError
    @errors << "Fields could not be read"
    []
  end

  def apply(items)
    existing = @form_type.form_custom_fields.to_a.index_by(&:id)
    attrs = []
    # The panel's order: an existing field by id, a new one by its name
    order = []

    items.each do |item|
      if item["id"].present?
        field = existing[item["id"].to_i]
        # E18 — removed by someone else meanwhile; E16 — regulatory fields are never changed here; X16 —
        # calculation fields (Ruby in meta_data) only by CapHive support (no local-environment exception here)
        next if field.nil? || field.reg_env.present? || (field.field_type == "Calculation" && !@user.support?)

        attrs << existing_attrs(field, item)
        order << field.id unless truthy?(item["_destroy"])
      else
        new_attr = new_field_attrs(item)
        next unless new_attr

        attrs << new_attr
        order << new_attr[:name]
      end
    end
    return if @errors.any?

    # X13 — a new field named like an existing (kept) one, or like another new one
    names = (existing.values - attrs.select { |a| a[:_destroy] }.filter_map { |a| existing[a[:id]] }).map(&:name) +
            attrs.reject { |a| a[:id] }.pluck(:name)
    names.tally.select { |_name, count| count > 1 }.each_key do |name|
      @errors << "A field named #{attrs.find { |a| a[:name] == name && a[:label] }&.dig(:label) || name.humanize} already exists"
    end
    return if @errors.any?

    unless @form_type.update(form_custom_fields_attributes: attrs)
      # The nested fields' messages come prefixed "Form custom fields <attribute> …"; show the rule itself
      @errors.concat(@form_type.errors.full_messages.map do |message|
        next "A field with that name already exists" if message == "Form custom fields name has already been taken"

        message.sub(/\AForm custom fields \w+(?: \w+)? (?=[A-Z])/, "")
      end.uniq)
      return
    end
    reslot(order)
  end

  # E17 — an existing field: only its label, flags and help text (never name, type, options, conditions, steps)
  def existing_attrs(field, item)
    label = item["label"].to_s.strip
    if label.length > LABEL_MAX
      @errors << "Labels can be at most #{LABEL_MAX} characters"
      return { id: field.id }
    end
    attrs = { id: field.id }
    attrs[:label] = label if label.present?
    FLAGS.each { |flag| attrs[flag.to_sym] = truthy?(item[flag]) if item.key?(flag) }
    attrs[:help_text] = item["help_text"].to_s if item.key?("help_text")
    payout_attrs(field, item, attrs)
    # H14 — removing deletes the definition; values stored on records stay. M14 X18 — a marked payout field is
    # removed only by CapHive support (removing it is an unmark)
    if truthy?(item["_destroy"])
      return refuse_payout_unmark(attrs) if field.payout_field.present? && !@user.support?

      attrs[:_destroy] = true
    end
    attrs
  end

  # M14 ⑨ H18, X17 — the payout mark of a KYC text field: set or switched by whoever may mark it; cleared only by
  # CapHive support. Other fields ignore the key (the model refuses a mark on them anyway, X19).
  def payout_attrs(field, item, attrs)
    return unless item.key?("payout_field") && (field.payout_markable? || field.payout_field.present?)

    requested = item["payout_field"].to_s.presence
    return if requested == field.payout_field
    return refuse_payout_unmark(attrs) if requested.nil? && !@user.support?

    attrs[:payout_field] = requested if FormCustomFieldPolicy.new(@user, field).mark_payout_field?
  end

  def refuse_payout_unmark(attrs)
    @errors << FormCustomField::PAYOUT_UNMARK_REFUSED unless @errors.include?(FormCustomField::PAYOUT_UNMARK_REFUSED)
    attrs
  end

  # H11 — a new field: name from its label, one of the offered types, options for Select (X15), the firm's
  # currency for Money (E20)
  def new_field_attrs(item)
    label = item["label"].to_s.strip
    field_type = item["field_type"].to_s
    if label.blank?
      @errors << "A new field needs a label"
    elsif label.length > LABEL_MAX
      @errors << "Labels can be at most #{LABEL_MAX} characters"
    elsif NEW_FIELD_TYPES.exclude?(field_type)
      @errors << "#{field_type.presence || 'That'} is not a field type the panel can add"
    elsif field_type == "Select" && item["options"].to_s.split(",").map(&:strip).none?(&:present?)
      @errors << "Add at least one option for #{label}"
    else
      attrs = { name: FormCustomField.to_name(label), label:, field_type:, help_text: item["help_text"].to_s }
      attrs[:meta_data] = item["options"].to_s if field_type == "Select"
      attrs[:meta_data] = @form_type.entity.currency if field_type == "Money"
      FLAGS.each { |flag| attrs[flag.to_sym] = truthy?(item[flag]) }
      return attrs
    end
    nil
  end

  # D15 — the fields the panel listed (kept and new, in the panel's order) take the positions they hold between
  # them after the update; fields it did not list (regulatory, locked calculations, removed) keep theirs
  def reslot(order)
    fields = @form_type.form_custom_fields.reload.to_a
    by_id = fields.index_by(&:id)
    by_name = fields.index_by(&:name)
    ordered = order.filter_map { |ref| ref.is_a?(Integer) ? by_id[ref] : by_name[ref] }.uniq
    slots = ordered.filter_map(&:position).sort
    FormCustomField.acts_as_list_no_update do
      ordered.each_with_index do |field, index|
        field.update!(position: slots[index]) if slots[index] && field.position != slots[index]
      end
    end
  end

  def truthy?(value)
    ActiveModel::Type::Boolean.new.cast(value) ? true : false
  end
end
