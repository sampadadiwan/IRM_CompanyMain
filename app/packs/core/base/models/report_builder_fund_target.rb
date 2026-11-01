# Where a fund choice goes in a Report Builder report: on the report's own
# rows when they have a fund (commitments, calls, remittances…), otherwise on
# every many-per-row related data whose rows have one (an investor's
# capital commitments and fund units). One rule for guided setup step 3 and
# for templates created with a fund.
#
# Worked examples: report-builder-live-builder H23, E22;
# report-builder-starting-points H4, H7 —
# openspec/changes/report-builder-starting-points/business-rules.md
class ReportBuilderFundTarget
  # { root: true, relations: [] } or { root: false, relations: ["capital_commitments", …] }
  def self.for(config)
    # The rows themselves belong to a fund
    return { root: true, relations: [] } if config.root_class.column_names.include?("fund_id")

    # Otherwise each related data with several rows per row whose rows have a fund
    relations = config.joins.map { |j| j[:relation].to_s }.select do |relation|
      config.column_type.strategy_for(relation) == :grouped &&
        ReportBuilderColumnCatalog.related_class(config.root_class, relation)&.column_names&.include?("fund_id")
    end
    { root: false, relations: relations }
  end
end
