# Bridges investor access from a feeder fund up to its master fund.
#
# Master/feeder structures are common here: an investor's AccessRight is
# granted on the feeder fund (the one they actually invested through), never
# on the master fund directly. But fund-scoped data such as
# PortfolioInvestment / AggregatePortfolioInvestment usually lives on the
# master fund. A plain `for_investor` check only looks at the record's own
# fund, so without this bridge an investor with feeder-only access would see
# nothing for the master fund.
#
# This is a plain helper module (not mixed into Fund) -- it exists only for
# PortfolioInvestmentPolicy and AggregatePortfolioInvestmentPolicy, both of
# which need the exact same rule for both their Scope#resolve (index) and
# show? (single record), and previously drifted apart because each
# duplicated this logic inline.
module FeederMasterFundAccess
  module_function

  # All fund ids whose fund-scoped data (PIs, APIs) this investor may see:
  # funds they have a direct AccessRight on, plus any master fund reachable
  # through a feeder fund they have direct access to.
  #
  # Used by Policy::Scope#resolve to filter a list of PI/API records down to
  # the ones whose fund_id is in this set.
  def eligible_ids_for_investor(user)
    # Funds with a direct AccessRight -- same check `super` would have run
    # via FundBasePolicy::Scope, just executed against Fund instead of the
    # PI/API model so the join lands on the fund that actually owns the
    # AccessRight.
    direct_ids = Fund.for_investor(user).pluck(:id)

    # Among those directly-accessible funds, find the ones that are feeders
    # (master_fund_id set) and pull out their master fund ids. .distinct
    # because multiple feeder funds can point at the same master fund.
    master_ids_via_feeder = Fund.where(id: direct_ids)
                                .where.not(master_fund_id: nil)
                                .distinct
                                .pluck(:master_fund_id)

    direct_ids + master_ids_via_feeder
  end

  # Single-fund version of the same rule, for Policy#show? where we only
  # have one record's fund to check rather than a list to filter.
  def accessible_to_investor?(user, fund)
    eligible_ids_for_investor(user).include?(fund.id)
  end
end
