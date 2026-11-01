# The calculations the wizard offers for the columns a report already has,
# and the name it suggests at the end.
#
#   Called %   call_amount, committed_amount           IF([committed] > 0, [call] / [committed] * 100, 0)
#   Unpaid     call_amount, collected_amount           [call] - [collected]
#   Uncalled   committed_amount, call_amount           [committed] - [call]
#   DPI        distribution_amount, collected_amount   IF([collected] > 0, [distribution] / [collected], 0)
#
# Both columns must come from the same place (the row itself, or the same
# related data). Worked examples H25, H26, H27, E24, E25 —
# openspec/changes/report-builder-live-builder/business-rules.md
class ReportBuilderSuggestions
  RULES = [
    { name: "Called %", needs: %w[call_amount committed_amount], in_words: "Called as a share of committed",
      expression: "IF([%<committed_amount>s] > 0, [%<call_amount>s] / [%<committed_amount>s] * 100, 0)" },
    { name: "Unpaid", needs: %w[call_amount collected_amount], in_words: "Called but not yet collected",
      expression: "[%<call_amount>s] - [%<collected_amount>s]" },
    { name: "Uncalled", needs: %w[committed_amount call_amount], in_words: "Committed but not yet called",
      expression: "[%<committed_amount>s] - [%<call_amount>s]" },
    { name: "DPI", needs: %w[distribution_amount collected_amount], in_words: "Distributed for each unit paid in",
      expression: "IF([%<collected_amount>s] > 0, [%<distribution_amount>s] / [%<collected_amount>s], 0)" }
  ].freeze

  class << self
    # [{ name:, expression:, in_words:, added: }] — one per rule whose columns are in the report
    def for(config, gvps)
      by_source = column_keys(gvps).group_by { |key| key.include?(".") ? key.rpartition(".").first : "" }
      labels = (config.formulas || []).map { |f| f["label"].to_s }

      RULES.filter_map do |rule|
        # The first place (row or related data) that has both columns
        prefix, = by_source.find { |_, keys| rule[:needs].all? { |n| keys.map { |k| k.split(".").last }.include?(n) } }
        next unless prefix

        keys = rule[:needs].to_h { |n| [n.to_sym, prefix.empty? ? n : "#{prefix}.#{n}"] }
        { name: rule[:name], expression: format(rule[:expression], keys), in_words: rule[:in_words],
          added: labels.include?(rule[:name]) }
      end
    end

    # "Investors — Committed, Called — Growth Fund II": the table, the first two
    # columns that aren't the row's own name, and the fund when one is chosen (H27)
    def name(config, gvps, entity)
      table   = ReportBuilder::Wizard.model_label(config.root_model).pluralize
      columns = gvps.reject { |g| g.key.start_with?("formula:", "pivot:") || own_name?(config, g) }
                    .first(2).map { |g| g.label.presence || g.name }
      [table, columns.join(", ").presence, fund_name(config, entity)].compact.join(" — ")
    end

    private

    def column_keys(gvps)
      gvps.map { |g| g.key.split(";").first.to_s.strip }.reject { |k| k.start_with?("formula:", "pivot:") }
    end

    # investor_name on investors, name / full_name on any table
    def own_name?(config, gvp)
      key = gvp.key.split(";").first.to_s.strip
      %w[name full_name].include?(key) || key == "#{config.root_model.to_s.underscore}_name"
    end

    # The fund chosen in step 3, on the rows or on any related data
    def fund_name(config, entity)
      ids = [config.root_filters["fund_id_eq"]] +
            config.joins.map { |j| (j[:child_filters] || {}).stringify_keys["fund_id_eq"] }
      id = ids.compact_blank.first
      id && Fund.where(entity_id: entity.id).find_by(id: id)&.name
    end
  end
end
