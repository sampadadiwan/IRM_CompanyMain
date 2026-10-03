# One document card on the Document Checks settings page: its rows are saved together. Rows with an id
# are updated, rows without one are created, saved rows missing from the post are deleted — all in one
# transaction for this card only. Any invalid row blocks the card's save, with its error on the row.
#
#   form = DocChecks::CardForm.new(entity:, document_name: "CML", rows: params[:rows])
#   form.save   # => true / false; form.rows carries each row's errors
#
# See openspec/changes/document-checks/design.md (card ① Setup). Worked examples H2, E3, X4.
module DocChecks
  class CardForm
    ROW_ATTRIBUTES = %w[action field_name look_for tip replace_existing expected_answer].freeze

    attr_reader :entity, :record_type, :document_name, :rows

    def initialize(entity:, document_name:, rows: [], record_type: "InvestorKyc")
      @entity = entity
      @record_type = record_type
      @document_name = document_name.to_s.squish
      @existing = DocCheck.where(entity:, record_type:, document_name: @document_name).index_by(&:id)
      @rows = build_rows(row_list(rows))
    end

    def save
      return false unless valid?

      DocCheck.transaction do
        # Saved rows no longer on the card are deleted first, so a field they held is free again
        removed = @existing.keys - @rows.filter_map(&:id)
        DocCheck.where(id: removed).find_each(&:destroy!)
        # Rows whose field or look-for changed are parked first, so two rows can swap fields without
        # tripping the unique indexes mid-way
        @rows.select { |row| row.persisted? && (row.field_name_changed? || row.look_for_changed?) }.each do |row|
          row.class.where(id: row.id).update_all(field_name: nil, look_for: "__moving_#{row.id}")
          # Both parked columns must be written back by save! — it only writes attributes marked changed
          row.field_name_will_change!
          row.look_for_will_change!
        end
        @rows.each_with_index do |row, index|
          row.position = index
          row.save!
        end
      end
      true
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
      false
    end

    # Every row valid, and no field or look-for twice on the card (siblings the database can't see yet)
    def valid?
      @rows.each(&:valid?)
      flag_duplicates(:field_name, "Already used on this card") { |row| row.field_name&.downcase }
      flag_duplicates(:look_for, "Already on this card") { |row| row.look_for.to_s.downcase }
      @rows.all? { |row| row.errors.empty? }
    end

    def checks_count
      @rows.size
    end

    private

    # The form posts rows keyed per row (rows[r12][…], rows[n3][…]) so a checkbox's hidden companion can't
    # start a new row; keep the page order. Arrays (from the controller's own state) pass through.
    def row_list(rows)
      rows = rows.to_unsafe_h if rows.respond_to?(:to_unsafe_h)
      rows.is_a?(Hash) ? rows.values : Array(rows)
    end

    def build_rows(raw_rows)
      raw_rows.map do |raw|
        attrs = (raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h).stringify_keys
        row = @existing[attrs["id"].to_i] || DocCheck.new(entity:, record_type:, document_name:)
        row.assign_attributes(attrs.slice(*ROW_ATTRIBUTES).merge("replace_existing" => attrs["replace_existing"].in?([true, "1", "true"])))
        row.card_checked = true
        row
      end
    end

    # Model uniqueness only sees saved rows; two new rows with the same field are caught here
    def flag_duplicates(attribute, message, &)
      @rows.group_by(&).each do |key, rows|
        next if key.blank? || rows.size < 2

        rows.drop(1).each { |row| row.errors.add(attribute, message) unless row.errors.added?(attribute, message) }
      end
    end
  end
end
