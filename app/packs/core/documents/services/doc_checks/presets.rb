# Ready-made checks for common documents (config/doc_check_presets.yml). A preset only adds what it can
# map to a field the record type allows and that isn't already on the card; the rest is reported as
# "Not added", so applying a preset never leaves an incomplete row behind.
# See openspec/changes/document-checks/design.md (card ① Setup). Worked examples H1, E4, E5.
module DocChecks
  class Presets
    Applied = Struct.new(:rows, :not_added, keyword_init: true)

    def self.all
      @all ||= YAML.load_file(Rails.root.join("config/doc_check_presets.yml")).deep_symbolize_keys.freeze
    end

    # The preset a document name offers, or nil ("Board Resolution" offers none)
    def self.key_for(document_name)
      all.find { |_key, preset| document_name.to_s.match?(Regexp.new(preset[:pattern], Regexp::IGNORECASE)) }&.first&.to_s
    end

    def self.name_for(key)
      all.dig(key.to_sym, :name)
    end

    # Unsaved rows for the preset's checks that map to an allowed field and aren't on the card yet.
    #   existing - the card's current checks (saved or not), to skip what's already there
    def self.rows_for(entity:, document_name:, key:, existing:, record_type: "InvestorKyc")
      preset = all.fetch(key.to_sym)
      fields = Registry.for(record_type).fields_for(entity)
      used_fields = existing.filter_map(&:field_name).to_set(&:downcase)
      used_look_fors = existing.to_set { |c| c.look_for.to_s.downcase }
      rows = []
      not_added = []

      preset[:checks].each do |entry|
        look_for = entry[:look_for].to_s
        # Already on the card: nothing to add, nothing to report. Worked example E4.
        next if used_look_fors.include?(look_for.downcase)

        field = pick_field(entry, fields, used_fields)
        if entry[:action] != "question" && field.nil?
          # No field on the record's form for it. Worked example H1 ("Not added: Email, Mobile").
          not_added << look_for unless already_mapped?(entry, fields, used_fields)
          next
        end

        used_fields << field.name.downcase if field
        rows << DocCheck.new(entity:, record_type:, document_name:, action: entry[:action], field_name: field&.name,
                             look_for:, tip: entry[:tip])
      end
      Applied.new(rows:, not_added:)
    end

    # The first candidate field the record type allows and the card doesn't use yet
    def self.pick_field(entry, fields, used_fields)
      Array(entry[:fields]).each do |candidate|
        field = fields.find { |f| f.name.casecmp?(candidate.to_s) }
        return field if field && used_fields.exclude?(field.name.downcase)
      end
      nil
    end

    # A candidate exists but the card already uses it (under another look-for): skipped, not "Not added"
    def self.already_mapped?(entry, fields, used_fields)
      Array(entry[:fields]).any? { |candidate| fields.any? { |f| f.name.casecmp?(candidate.to_s) } && used_fields.include?(candidate.to_s.downcase) }
    end
    private_class_method :pick_field, :already_mapped?
  end
end
