# What the custom fields side panel shows: its title and note and the form type's fields.
# openspec/changes/grid-columns-inline-settings — design card ③ (phase 4); H10, E14, E16, E21
module FormTypeFieldsHelper
  # "Investor fields", "Capital commitment fields"
  def form_type_fields_title(model_class)
    "#{model_class.model_name.human} fields"
  end

  # The one-line "who shares this" note, and its fuller tooltip
  def form_type_fields_note(model_class, form_type)
    human = model_class.model_name.human
    tag = form_type.tag.presence || "Default"
    ["Shared by every #{human.downcase} on the #{tag} form type",
     "These fields belong to the #{human} form type '#{tag}' of your firm: all #{human.pluralize.downcase} using it — " \
     "their form, page, imports and exports — show the change."]
  end

  # The listed fields, in form order: regulatory ones left out (E16); calculation fields locked unless the user is
  # CapHive support (E14, E15)
  # @return [Array<Hash>] { id:, name:, label:, field_type:, required:, read_only:, internal:, help_text:, locked: }
  def form_type_fields_rows(form_type, user)
    return [] unless form_type.persisted?

    form_type.form_custom_fields.not_regulatory.order(:position).map do |field|
      { id: field.id, name: field.name, label: field.human_label, field_type: field.field_type, required: field.required,
        read_only: field.read_only, internal: field.internal, help_text: field.help_text.to_s, removed: false,
        locked: field.field_type == "Calculation" && !user.support? }.merge(form_type_field_payout(field, form_type, user))
    end
  end

  # M14 ⑨ H18, X17, X18 — the payout mark of a KYC text field: its kind, whether this user may set it (company admin
  # or support), and whether it is locked (marked, and the user is not CapHive support: no unmark, no remove)
  def form_type_field_payout(field, form_type, user)
    markable = field.field_type == "TextField" && FormCustomField::PAYOUT_FORM_TYPES.include?(form_type.name) &&
               FormCustomFieldPolicy.new(user, field).mark_payout_field?
    { payout_field: field.payout_field.to_s, payout_markable: markable,
      payout_locked: field.payout_field.present? && !user.support? }
  end

  # X13–X15 — the panel again after a refused save, from the list as submitted
  def form_type_fields_rows_from_submission(form_type, user, json)
    items = begin
      JSON.parse(json.to_s)
    rescue JSON::ParserError
      []
    end
    items = [] unless items.is_a?(Array)
    saved = form_type_fields_rows(form_type, user).index_by { |row| row[:id] }
    rows = items.filter_map do |item|
      next unless item.is_a?(Hash)

      if item["id"].present?
        row = saved[item["id"].to_i]
        next unless row

        overrides = { label: item["label"].presence || row[:label], help_text: item["help_text"].to_s,
                      removed: ActiveModel::Type::Boolean.new.cast(item["_destroy"]) ? true : false }
        # M14 — a refused unmark shows the stored mark again; a new choice is kept
        overrides[:payout_field] = item["payout_field"].to_s if item.key?("payout_field") && !row[:payout_locked]
        FormTypeFieldsSave::FLAGS.each { |flag| overrides[flag.to_sym] = ActiveModel::Type::Boolean.new.cast(item[flag]) }
        row.merge(overrides)
      else
        { id: nil, name: FormCustomField.to_name(item["label"].to_s.presence || "new"), label: item["label"].to_s,
          field_type: item["field_type"].to_s, options: item["options"].to_s, required: false, read_only: false,
          internal: false, help_text: item["help_text"].to_s, removed: false, locked: false, payout_field: "",
          payout_markable: false, payout_locked: false }
      end
    end
    # Locked rows (calculations for non-support) are never submitted: keep them in the list
    listed = rows.filter_map { |row| row[:id] }
    rows + saved.values.select { |row| row[:locked] && listed.exclude?(row[:id]) }
  end
end
