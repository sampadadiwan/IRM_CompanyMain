# Decides which columns a table offers in the Report Builder:
#   - columns_for          readable on the report's own rows (shown as columns)
#   - filter_only_for      searchable but with no readable value (filters only)
#   - filter_columns_for   everything searchable (the filter field list)
#   - related_columns_for  stored fields only, for related data (they're totalled in SQL)
# and how to read a root column's value, including the few that the grids
# show through a decorator (READERS mirrors those decorators as plain text,
# because decorators return links and need a request).
#
# Worked examples H6, E12, E13, E14 — openspec/changes/report-builder-trust/design.md#worked-examples
class ReportBuilderColumnCatalog
  # Plain-text readers for columns that only exist on a Draper decorator, keyed
  # by model then column, with the association each needs preloaded (so export
  # doesn't run one query per row).
  READERS = {
    "CapitalCommitment" => {
      "investor_kyc_full_name" => { read: ->(r) { r.investor_kyc&.full_name }, preload: :investor_kyc }
    },
    "CapitalRemittance" => {
      "investing_entity_name" => { read: ->(r) { r.investor_kyc&.full_name || r.investor_name }, preload: :investor_kyc }
    },
    "CapitalDistributionPayment" => {
      "investing_entity_name" => { read: ->(r) { r.investor_kyc&.full_name || r.investor_name }, preload: :investor_kyc }
    },
    "AggregatePortfolioInvestment" => {
      "investment_instrument_name" => { read: ->(r) { r.investment_instrument&.name }, preload: :investment_instrument }
    },
    "PortfolioInvestment" => {
      "investment_instrument_name" => { read: ->(r) { r.investment_instrument&.name }, preload: :investment_instrument }
    },
    "KpiReport" => {
      # Same rule as the grid's "For" partial: the portfolio company, else the entity
      "entity_name" => { read: ->(r) { r.portfolio_company&.investor_name || r.entity&.name }, preload: %i[portfolio_company entity] },
      "user_name" => { read: ->(r) { r.user&.full_name }, preload: :user }
    },
    "InvestorKyc" => {
      "expired" => { read: ->(r) { r.expired? }, preload: nil }
    }
  }.freeze

  class << self
    # Columns that can be shown on the report's own rows (H6, E12, E14)
    def columns_for(klass)
      return [] unless klass

      candidates(klass).select { |c| readable?(klass, c[:key]) }
    end

    # Searchable fields with no readable value — offered as filters only (E12)
    def filter_only_for(klass)
      return [] unless klass

      candidates(klass).reject { |c| readable?(klass, c[:key]) }
    end

    # Every searchable field: the filter field list for root and related data
    def filter_columns_for(klass)
      return [] unless klass

      candidates(klass)
    end

    # Related data is totalled in SQL, so only stored columns can be offered (E13)
    def related_columns_for(klass)
      return [] unless klass

      stored = klass.column_names.to_set
      candidates(klass).select { |c| stored.include?(c[:key]) || stored.include?("#{c[:key]}_cents") }
    end

    # Associations to preload on the root query for the selected root columns
    def preloads_for(klass, keys)
      readers = READERS[klass.name] || {}
      keys.filter_map { |k| readers.dig(k, :preload) }.flatten.uniq
    end

    # A root column's value: the record's own attribute or method, else the
    # Report Builder reader. Errors read as blank, never break the report (X6).
    def read(record, key)
      if record.respond_to?(key)
        record.public_send(key)
      elsif (reader = READERS.dig(record.class.name, key, :read))
        reader.call(record)
      end
    rescue StandardError => e
      Rails.logger.warn "[ReportBuilder] could not read #{record.class.name}##{key} id=#{record.id}: #{e.message}"
      nil
    end

    KIND_GROUPS = [
      [:amounts, "Amounts", %i[money number integer]],
      [:dates, "Dates", %i[date datetime]],
      [:yes_no, "Yes/No", %i[boolean]],
      [:text, "Names & text", nil]
    ].freeze

    TYPE_ICONS = { money: "ti-cash", number: "ti-hash", integer: "ti-hash", date: "ti-calendar",
                   datetime: "ti-calendar-time", boolean: "ti-toggle-left" }.freeze

    # The picker's columns for one source — the row's own (relation nil) or a
    # related data — grouped by kind, without internal id / cents fields, and
    # with a hint wherever two columns share a label. Worked examples H3, E3.
    def grouped_for(config, relation = nil)
      klass = relation ? related_class(config.root_class, relation) : config.root_class
      return [] unless klass

      cols = relation ? related_columns_for(klass) : columns_for(klass)
      cols = cols.reject { |c| c[:key].end_with?("_id", "_cents") }
      duplicate_labels = cols.group_by { |c| c[:label].downcase }.select { |_, v| v.size > 1 }.keys

      entries = cols.map do |c|
        full_key = relation ? "#{relation}.#{c[:key]}" : c[:key]
        type = config.column_type.base_type(full_key)
        { key: full_key, raw_key: relation ? "#{relation}.#{c[:raw_key]}" : c[:raw_key], label: c[:label],
          hint: (c[:key] if duplicate_labels.include?(c[:label].downcase)), type: type,
          icon: TYPE_ICONS[type] || "ti-abc" }
      end

      KIND_GROUPS.filter_map do |kind, label, types|
        members = entries.select do |e|
          types ? types.include?(e[:type]) : KIND_GROUPS.none? { |_, _, t| t&.include?(e[:type]) }
        end
        { kind: kind, label: label, columns: members } if members.any?
      end
    end

    # The model at the end of a related-data path, or nil
    def related_class(root_class, relation)
      relation.to_s.split(".").reduce(root_class) do |klass, part|
        klass&.reflect_on_association(part.to_sym)&.klass
      end
    rescue StandardError
      nil
    end

    # Label for a column key as the catalog names it (bulk add takes labels
    # from here, never from the browser)
    def label_for(config, key)
      clean = key.to_s.split(";").first.to_s.strip
      parts = clean.split(".")
      field = parts.pop
      klass = parts.any? ? related_class(config.root_class, parts.join(".")) : config.root_class
      list = parts.any? ? related_columns_for(klass) : columns_for(klass)
      list.find { |c| c[:key] == field }&.dig(:label) || field.humanize
    end

    # Drops cached probe instances — called by the Rails reloader in development
    def reset_cache!
      @probes = nil
    end

    def readable?(klass, key)
      return true if READERS.dig(klass.name, key)

      probe = probe_for(klass)
      probe ? probe.respond_to?(key) : klass.column_names.include?(key)
    end

    private

    # The candidate list (same sources and shape as the old
    # ReportBuilderController#columns_for_model): ransackable attributes, then
    # STANDARD_COLUMNS / ADDITIONAL_COLUMNS for nicer labels, else DB columns.
    def candidates(klass)
      cols_by_key = {}

      # 1. Ransackable attributes
      if klass.respond_to?(:ransackable_attributes)
        klass.ransackable_attributes.each do |attr|
          cols_by_key[attr] = { label: attr.humanize, key: attr }
        end
      end

      # 2. Standard and 3. additional columns overlay labels and col-type hints
      %i[STANDARD_COLUMNS ADDITIONAL_COLUMNS].each do |const|
        next unless klass.const_defined?(const)

        klass.const_get(const).each do |label, key|
          clean_key = key.to_s.split(";").first.strip
          cols_by_key[clean_key] = { label: label, key: key }
        end
      end

      # 4. Fallback to DB columns if still empty
      if cols_by_key.empty?
        klass.column_names.each do |name|
          next if %w[id entity_id created_at updated_at deleted_at].include?(name)

          cols_by_key[name] = { label: name.humanize, key: name }
        end
      end

      cols_by_key.values.map do |c|
        {
          label: c[:label].to_s.split(";").first.strip,
          key: c[:key].to_s.split(";").first.strip,
          raw_key: c[:key],
          raw_label: c[:label]
        }
      end.sort_by { |c| c[:label] }
    end

    # A blank instance tells attributes and methods apart from ransackers
    # without touching data; cached per class.
    def probe_for(klass)
      @probes ||= {}
      @probes[klass.name] ||= begin
        klass.new
      rescue StandardError
        nil
      end
    end
  end
end
