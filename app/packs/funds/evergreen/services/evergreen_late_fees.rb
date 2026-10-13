# Late management fees for a class's NAV draft (R9.10–R9.18): fee entries dated in an already-approved
# period that no NAV has accounted for, found by sums alone — the ledger since the class's last uploaded
# NAV, up to its previous approved computed NAV, minus what those approved NAVs accounted for
# (FundNav#mgmt_fee_accounted_cents). Never loads account_entries rows (CLAUDE.md).
# openspec/changes/archive/2026-10-11-evergreen-late-management-fees/design.md#③-late-fee-finder
class EvergreenLateFees
  # late_cents: late accruals; decided / included: what the draft's decisions cover; late_paid_cents:
  # late fee payments of the whole fund (always included, R9.17); periods: approved NAVs whose period
  # received late entries; redeemed_investors: investors with redemptions dealt since the earliest of them;
  # reopenable: those periods no dealing date was priced at (R9.16)
  Result = Data.define(:late_cents, :decided_cents, :included_cents, :late_paid_cents, :periods, :pct_of_nav,
                       :redeemed_investors, :reopenable) do
    # R9.13: what still needs the approver's choice
    def outstanding_cents
      [late_cents - decided_cents, 0].max
    end

    def any?
      late_cents.positive? || late_paid_cents.positive?
    end
  end

  # Ledger sums are unrounded and each NAV stores what it accounted for to 2 decimals, so a dozen NAVs can
  # leave a few hundredths of a paisa between them. Less than one currency unit is rounding, not a late fee
  # — never something to block approval over.
  TOLERANCE_CENTS = 100

  def self.call(fund, unit_type, nav_date, draft: nil)
    new(fund, unit_type, nav_date, draft:).call
  end

  # R9.17: late payments are fund-level ledger entries, split between classes like any payment, so they are
  # found for the fund: payments since the latest uploaded NAV of any class, dated on or before the latest
  # approved computed NAV, minus the payments those NAVs accounted for
  def self.late_paid_cents(fund, nav_date)
    approved = FundNav.approved.where(fund_id: fund.id, nav_date: ...nav_date)
    upload = approved.where(source: "uploaded").maximum(:nav_date)
    last = approved.where(source: "computed").maximum(:nav_date)
    return 0.to_d if last.nil? || (upload && last <= upload)

    ledger = NavInputs.new(fund, last).ledger_sum_cents(fund.evergreen_fund_setting.mgmt_fee_paid_entry_name, upload, last)
    accounted = approved.where(source: "computed", nav_date: (upload ? upload + 1.day : Date.new(1900))..last)
                        .sum(:mgmt_fee_paid_accounted_cents).to_d
    beyond_rounding(ledger - accounted)
  end

  def self.beyond_rounding(cents)
    cents > TOLERANCE_CENTS ? cents.round(2) : 0.to_d
  end

  def initialize(fund, unit_type, nav_date, draft: nil)
    @fund = fund
    @unit_type = unit_type
    @nav_date = nav_date
    @draft = draft
  end

  def call
    navs = FundNav.approved.where(fund_id: @fund.id, unit_type: @unit_type, nav_date: ...@nav_date)
    # E330, E331: a period covered by an uploaded NAV is never late — the window starts after the latest one
    upload = navs.where(source: "uploaded").maximum(:nav_date)
    computed = navs.where(source: "computed").where(upload ? ["nav_date > ?", upload] : {}).order(:nav_date).to_a
    late = computed.empty? ? 0.to_d : late_accruals(computed, upload)
    periods = late.positive? ? late_periods(computed, upload) : []
    decided = @draft ? @draft.late_decided_cents : 0.to_d
    Result.new(late_cents: late, decided_cents: decided, included_cents: @draft ? @draft.late_included_cents : 0.to_d,
               late_paid_cents: self.class.late_paid_cents(@fund, @nav_date), periods:,
               pct_of_nav: @draft&.nav_cents.to_d&.positive? ? (late / @draft.nav_cents.to_d * 100).round(2) : nil,
               redeemed_investors: periods.empty? ? 0 : redeemed_since(periods.first.nav_date),
               reopenable: reopenable(periods))
  end

  private

  # H105: everything accrued in (upload, previous computed NAV] less what those approved NAVs accounted for.
  # E332: entries dated after the previous NAV are this draft's own period, counted by the builder, not late.
  # E341: a negative difference (entries reversed after approval) is treated as nothing late
  def late_accruals(computed, upload)
    ledger = sums(upload, computed.last.nav_date).values.sum
    self.class.beyond_rounding(ledger - computed.sum { |n| n.mgmt_fee_accounted_cents.to_d })
  end

  # The approved NAVs whose own period now holds more than they took in: their window's ledger sum today
  # exceeds what they accounted for from it (accounted less the late amounts decided on them)
  def late_periods(computed, upload)
    by_date = sums(upload, computed.last.nav_date)
    from = upload
    computed.select do |nav|
      window = by_date.sum { |date, cents| date > (from || Date.new(1900)) && date <= nav.nav_date ? cents : 0 }
      from = nav.nav_date
      window - (nav.mgmt_fee_accounted_cents.to_d - nav.late_decided_cents) > TOLERANCE_CENTS
    end
  end

  def sums(after, upto)
    @sums ||= NavInputs.new(@fund, upto).mgmt_fee_sums_by_date(@unit_type, after, upto)
  end

  # E338: investors of this class who redeemed after the late fee's period — they would not bear it if it
  # were included. Other classes never bear this class's fee, so their redemptions don't count
  def redeemed_since(from)
    DealingFill.joins(:dealing_order, :dealing_date)
               .where(fund_id: @fund.id, kind: "redemption", unit_type: @unit_type).where("dealing_fills.units > 0")
               .where(dealing_dates: { date: (from + 1.day)..@nav_date })
               .distinct.count("dealing_orders.investor_id")
  end

  # E339 / E340: a period's NAV can be reopened only when no dealing date was priced at it (R8.6)
  def reopenable(periods)
    used = DealingFill.where(fund_nav_id: periods.map(&:id)).distinct.pluck(:fund_nav_id)
    periods.reject { |nav| used.include?(nav.id) }
  end
end
