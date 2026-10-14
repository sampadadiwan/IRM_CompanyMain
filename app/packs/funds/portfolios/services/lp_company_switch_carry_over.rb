# One-time carry-over from the retired per-holding "Show Portfolio" flag to the company's Show to LPs switch: a
# portfolio company whose live holding had the flag on stays openable by its LPs. Run by the release migration.
#
# - E48 one holding with the flag on is enough (mixed holdings carry over as on)
# - E49 idempotent: only switches that are still off change
# - E51 deleted and snapshot holdings are ignored
# - X19 holdings whose company no longer exists are skipped and counted
# Worked examples H17, E48, E49, E51, X19 — openspec/changes/lp-folio-portfolio-dashboard/business-rules.md
class LpCompanySwitchCarryOver
  Result = Struct.new(:changed, :skipped, keyword_init: true)

  def self.call
    # Companies of live, non-snapshot holdings with the flag on
    company_ids = AggregatePortfolioInvestment.where(show_portfolio: true, snapshot: [false, nil])
                                              .distinct.pluck(:portfolio_company_id)
    existing_ids = Investor.where(id: company_ids).pluck(:id)
    changed = Investor.where(id: existing_ids, show_to_lps: false).update_all(show_to_lps: true, updated_at: Time.current)
    Result.new(changed:, skipped: company_ids.size - existing_ids.size)
  end
end
