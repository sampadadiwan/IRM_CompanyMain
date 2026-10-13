# A cheap fingerprint of a NAV's inputs, compared on read to flag drafts (and approved NAVs) whose
# inputs changed after they were built. Indexed aggregates, all fund-scoped; nothing is watched on
# write, so the account_entries write path is untouched.
# Worked examples E10, E11 — openspec/changes/open-ended-funds/design.md#worked-examples
#
# Review fix 2 (10 Oct 2026): a stale draft can no longer be approved, so "stale" must mean "this
# NAV's figures would change". The first version also hashed EVERY dealing fill and redemption
# payment of the fund, undated — so confirming any later dealing date, or paying any later
# redemption, marked every older NAV stale. The current fingerprint only reads dealing activity
# dated on or before the NAV date, which is all the NAV builder reads (NavInputs#advance_subscriptions
# / #unpaid_redemptions).
class NavStaleness
  # Current fingerprint, written by FundNavBuilder
  def self.fingerprint(fund_nav)
    digest("v2", common_parts(fund_nav) + dealing_parts(fund_nav))
  end

  # The first version's fingerprint (undated dealing aggregates). NAVs drafted before review fix 2
  # store this one; they stay "fresh" while it still matches, and switch to the current fingerprint
  # the next time they are drafted or recalculated. The column holds 64 characters, so there is no
  # room for a version prefix — FundNav#stale? simply accepts a match with either.
  def self.legacy_fingerprint(fund_nav)
    fund = fund_nav.fund
    legacy = [aggregate(DealingFill.where(fund_id: fund.id)), aggregate(CapitalDistributionPayment.where(fund_id: fund.id))]
    Digest::SHA256.hexdigest((common_parts(fund_nav) + legacy).join("|"))
  end

  def self.common_parts(fund_nav)
    fund = fund_nav.fund
    date = fund_nav.nav_date
    company_ids = fund.aggregate_portfolio_investments.distinct.pluck(:portfolio_company_id)
    [
      # Fund-level ledger balances (cash, other assets, liabilities, fee payments)
      aggregate(fund.fund_account_entries.where(reporting_date: ..date)),
      # Management-fee accruals of the class's folios
      aggregate(AccountEntry.where(fund_id: fund.id, entry_type: NavInputs::MGMT_FEE_ENTRY_TYPE, reporting_date: ..date)),
      # Units issued or cancelled on or before the date
      aggregate(FundUnit.where(fund_id: fund.id, issue_date: ..date)),
      # Valuations of the fund's holdings on or before the date
      aggregate(Valuation.where(owner_type: "Investor", owner_id: company_ids, valuation_date: ..date)),
      # Subscription money received on or before the date (E201–E204)
      aggregate(CapitalRemittancePayment.where(fund_id: fund.id, payment_date: ..date))
    ]
  end

  # Dealing activity the NAV actually reads, limited to the NAV date (review fix 2)
  def self.dealing_parts(fund_nav)
    fund = fund_nav.fund
    date = fund_nav.nav_date
    [
      # Dealing dates on or before the NAV date: confirm / undo / close changes which redemptions are
      # dealt-but-unpaid and which subscriptions roll past the NAV date
      aggregate(DealingDate.where(fund_id: fund.id, date: ..date)),
      # Fills of those dates (units and payouts dealt on or before the NAV date)
      aggregate(DealingFill.joins(:dealing_date).where(fund_id: fund.id, dealing_dates: { date: ..date })),
      # Redemption payouts dated on or before the NAV date (paid by then, so no longer owed)
      aggregate(CapitalDistributionPayment.where(fund_id: fund.id, payment_date: ..date))
    ]
  end

  def self.digest(version, parts)
    Digest::SHA256.hexdigest(([version] + parts).join("|"))
  end

  def self.aggregate(scope)
    count, updated = scope.pick(Arel.sql("COUNT(*)"), Arel.sql("MAX(#{scope.klass.table_name}.updated_at)"))
    "#{count}:#{updated}"
  end
end
