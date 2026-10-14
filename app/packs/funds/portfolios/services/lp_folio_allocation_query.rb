# The two account_entries reads behind the LP visible set. account_entries is very large, so every query is
# driven by capital_commitment_id + fund_formula_id (MySQL intersects their two single-column indexes), selects
# only narrow columns and dedups in SQL (CLAUDE.md large-table rules).
# Worked examples H2, E10–E21, E28a — openspec/changes/lp-folio-portfolio-dashboard/business-rules.md
class LpFolioAllocationQuery
  # Holding-level subjects only: instrument purchases and aggregated holdings (E21)
  PARENT_TYPES = %w[PortfolioInvestment AggregatePortfolioInvestment].freeze

  # [[capital_commitment_id, fund_formula_id], ...] -> [[parent_type, parent_id], ...] with a non-zero entry.
  # Each commitment is paired with the allocation formula of the fund it sits in, so a feeder folio is read
  # with the feeder fund's formula (E28a). Other formulas never count (E11, E14, E16, E20).
  def self.membership(pairs)
    return [] if pairs.empty?

    allocation_entries(pairs)
      # E12/E13 — less than one minor unit is noise; negatives count (E15)
      .where("ABS(account_entries.amount_cents) >= 1")
      .distinct
      .pluck(:parent_type, :parent_id)
  end

  # Own share: for each (commitment, formula) pair, the entry with the latest reporting date per subject on or
  # before today (E29, E30), ignoring deleted ones (E31). Ranked per purchase, so purchases with different
  # latest dates are each counted once (E33). Returns [[parent_type, parent_id, fund_formula_id, amount_cents]].
  def self.latest_amounts(pairs)
    return [] if pairs.empty?

    ranked = allocation_entries(pairs).select(
      "account_entries.parent_type, account_entries.parent_id, account_entries.fund_formula_id, account_entries.amount_cents, " \
      "ROW_NUMBER() OVER (PARTITION BY account_entries.capital_commitment_id, account_entries.parent_type, " \
      "account_entries.parent_id, account_entries.fund_formula_id ORDER BY account_entries.reporting_date DESC) AS row_rank"
    )
    AccountEntry.unscoped.from(ranked, :ranked).where("ranked.row_rank = 1")
                .pluck("ranked.parent_type", "ranked.parent_id", "ranked.fund_formula_id", "ranked.amount_cents")
  end

  # Base filter shared by membership and own share: the given (commitment, formula) pairs, holding-level
  # parents, not deleted (E19), dated on or before today (E17/E18 — every earlier date counts, so an exited
  # holding stays visible, E20a)
  def self.allocation_entries(pairs)
    pair_sql = pairs.map { "(account_entries.capital_commitment_id = ? AND account_entries.fund_formula_id = ?)" }.join(" OR ")
    AccountEntry.where(pair_sql, *pairs.flatten)
                .where(parent_type: PARENT_TYPES, deleted_at: nil)
                .where(reporting_date: ..Time.zone.today)
  end
end
