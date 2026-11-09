# ④ Saves the columns side panel: makes the owner's grid_view_preferences match the submitted list — order,
# headings, additions and removals — in one transaction under a row lock on the owner, or removes them all on a
# reset. openspec/changes/grid-columns-inline-settings — design D4, D5, D6; lld.md › Method Contracts
class GridColumnsSave
  MAX_ROWS = 100
  LABEL_MAX = 100
  KEY_MAX = 255
  # D20 — the data types and alignments Configure Grids offered
  # Boolean renders as a Yes/No badge (display_boolean) in both the HTML grid and AG Grid
  DATA_TYPES = %w[String Number Decimal Date Boolean HTML].freeze
  ALIGNMENTS = %w[text-start text-center text-end].freeze

  Result = Struct.new(:success, :errors, :owner) do
    def success? = success
  end

  def self.call(...)
    new(...).call
  end

  # @param user [User] the admin saving (already authorized by the controller)
  # @param context [GridColumnsContext] what the table showed, from the signed token
  # @param rows [String] JSON array of { "id" => saved row id } or { "key" => new key } or
  #   { "derived" => true, "key" => typed key } (D20), each with a "label" and optionally "data_type", "alignment"
  # @param reset [Boolean] H6 — remove every saved column of the owner
  def initialize(user:, context:, rows:, reset: false)
    @user = user
    @context = context
    @raw_rows = rows
    @reset = ActiveModel::Type::Boolean.new.cast(reset)
    @errors = []
  end

  def call
    rows = parse_rows
    return failure if @errors.any?

    owner = @context.owner
    ActiveRecord::Base.transaction do
      # H4 — the firm's form type for the record type is created on the first save (tag defaults to "Default")
      owner.save! if owner.new_record?
      # D4 — serialise saves of the same owner (two admins, a double click — E6): the later one replaces the set
      owner.lock!
      # One touch after commit instead of one per row; no list shuffling while positions are set explicitly
      ActiveRecord::Base.no_touching do
        GridViewPreference.acts_as_list_no_update do
          @reset ? owner.grid_view_preferences.destroy_all : replace_rows(owner, rows)
        end
      end
      raise ActiveRecord::Rollback if @errors.any?
    end
    return failure if @errors.any?

    # D10 — what the table header's column cache is keyed on
    owner.is_a?(Report) ? owner.touch : owner.entity.touch
    Result.new(success: true, errors: [], owner:)
  end

  # The label column holds an override only. E7 — a blank heading, or the column's own name, stores nothing so
  # the standard name shows; a "; css" alignment on the name is kept on a renamed heading. Also used by the
  # single-column Edit on Configure Grids (D19).
  def self.stored_label(label, name)
    label = label.to_s.strip
    clean_name = GridColumnOptions.clean(name)
    return nil if label.blank? || label == clean_name

    css = name.to_s.split(";", 2)[1]&.strip
    css.present? ? "#{label}; #{css}" : label
  end

  private

  def failure
    Result.new(success: false, errors: @errors, owner: @context.owner)
  end

  # The submitted list, or an error when it can't be read
  def parse_rows
    return [] if @reset

    rows = JSON.parse(@raw_rows.to_s)
    raise JSON::ParserError unless rows.is_a?(Array) && rows.size <= MAX_ROWS && rows.all?(Hash)

    rows
  rescue JSON::ParserError
    @errors << "Columns could not be read"
    []
  end

  def replace_rows(owner, rows)
    existing = owner.grid_view_preferences.index_by(&:id)
    resolved = resolve_rows(rows, existing)
    return if @errors.any?

    # X6 — the table needs at least one column
    if resolved.empty?
      @errors << "Keep at least one column"
      return
    end

    # Remove the saved columns that are no longer listed
    kept_ids = resolved.filter_map { |row| row[:preference]&.id }
    existing.each_value { |preference| preference.destroy! unless kept_ids.include?(preference.id) }

    # Update kept rows (heading, position) and create new ones, positions 1..n in the listed order
    resolved.each.with_index(1) do |row, position|
      if row[:preference]
        # E1 — heading and position; D20 — data type, alignment and (E24, derived only) key when the row sends them
        preference = row[:preference]
        attrs = { label: stored_label(row[:label], preference.name), sequence: position }.merge(row[:details])
        preference.update!(attrs)
      else
        name = row[:name]
        owner.grid_view_preferences.create!({ key: row[:key], name:, label: stored_label(row[:label], name),
                                              entity_id: owner.entity_id, sequence: position,
                                              derived_field: row[:derived] || nil }.merge(row[:details]))
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    @errors << e.record.errors.full_messages.to_sentence
  end

  # Each submitted row as { preference:, label: } (a saved row) or { key:, name:, label: } (a new one)
  def resolve_rows(rows, existing)
    seen = Set.new
    rows.filter_map do |row|
      label = row["label"].to_s.strip
      if label.length > LABEL_MAX
        @errors << "Headings can be at most #{LABEL_MAX} characters"
        next
      end

      details = row_details(row)
      next if details.nil?

      resolved = if row["id"].present? then saved_row(row, existing, details)
                 elsif ActiveModel::Type::Boolean.new.cast(row["derived"]) then derived_row(row, label)
                 else new_row(row)
                 end
      next unless resolved

      # E8 — a column listed twice is kept once, at its first position
      clean = GridColumnOptions.clean(resolved[:preference]&.key || resolved[:key])
      next unless seen.add?(clean)

      resolved.reverse_merge(details:).merge(label:)
    end
  end

  # D20 — the data type and alignment a row sends, checked against the lists Configure Grids offered; nil (and an
  # error) when one is not offered (X19). A row that sends neither changes neither.
  def row_details(row)
    details = {}
    if row.key?("data_type")
      data_type = row["data_type"].to_s.strip
      unless data_type.blank? || DATA_TYPES.include?(data_type)
        @errors << "#{data_type} is not a data type"
        return nil
      end
      details[:data_type] = data_type.presence
    end
    if row.key?("alignment")
      alignment = row["alignment"].to_s.strip
      unless alignment.blank? || ALIGNMENTS.include?(alignment) || alignment == row["stored_alignment"].to_s
        @errors << "#{alignment} is not an alignment"
        return nil
      end
      details[:alignment] = alignment.presence
    end
    details
  end

  # H18 — a new derived field: a typed key (free text, as Configure Grids allowed company admins) and its label
  def derived_row(row, label)
    key = row["key"].to_s.strip
    if key.blank? || label.blank?
      @errors << "A derived field needs a label and a key"
      return
    end
    if key.length > KEY_MAX
      @errors << "A derived field's key can be at most #{KEY_MAX} characters"
      return
    end
    { key:, name: label, derived: true }
  end

  # E5 — a saved row someone else removed meanwhile is skipped; a saved row keeps its stored key (never the
  # browser's) — except a derived field, whose key the user may retype (E24)
  def saved_row(row, existing, details)
    preference = existing[row["id"].to_i]
    return unless preference

    if preference.derived_field && row["key"].present?
      key = row["key"].to_s.strip
      if key.length > KEY_MAX
        @errors << "A derived field's key can be at most #{KEY_MAX} characters"
        return
      end
      details = details.merge(key:)
    end
    { preference:, details: }
  end

  # X4 — a new column must be offered in "Add a column" or have been shown by the table when the panel opened
  # (H3 — the first save from a page's standard columns). Keys become method chains on every row, so nothing
  # else is accepted.
  def new_row(row)
    clean = GridColumnOptions.clean(row["key"])
    shown = @context.shown.find { |_label, key| GridColumnOptions.clean(key) == clean }
    # The page's own label and key (with its "; css" alignment) when the table showed it
    return { key: shown[1], name: shown[0] } if shown

    option = options.call.values.flat_map(&:to_a).find { |_label, key| GridColumnOptions.clean(key) == clean }
    unless option
      @errors << "#{clean.presence || 'A blank column'} cannot be added"
      return
    end

    # Named by the label "Add a column" showed (standard, additional, list-only GRID_COLUMNS, related or custom
    # field), so a list-only column like "Name (link)" never falls back to a humanized key (D21)
    { key: option[1], name: option[0] }
  end

  def stored_label(label, name)
    self.class.stored_label(label, name)
  end

  def options
    @options ||= GridColumnOptions.new(@context.model_class, @context.entity.id)
  end
end
