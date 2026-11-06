# The one funds grid (R175, E203): every fund the user can see × the packs attached to them, with each
# attachment's classification · version and its latest outcome counts, the fund's open items, and the
# stats cards above it. Home draws it; /compliance/fund_packs (which used to draw a second matrix
# without per-row Attach) now sends people here. Plain standard table — the pack columns are dynamic,
# so it is not a RansackTable (R111).
#
# Cards are grid totals (stats-cards-equal-grid-totals): everything is computed from `funds`, the
# already-filtered and searched relation, so a filter or search moves the cards with the rows.
# All figures are SQL counts / small preloaded lists — no large table is materialised.
class ComplianceFundsGrid
  OUTCOMES = %w[breach needs_review could_not_check pass].freeze

  attr_reader :funds, :fund_packs, :packs, :open_counts, :outcomes_by_fp

  # fund_packs / items: the controller's policy_scope(FundCompliancePack / ComplianceRegisterItem), so
  # the action itself is policy-scoped (verify_policy_scoped) and the grid never widens what it sees
  def initialize(funds, fund_packs:, items:)
    @funds = funds.to_a
    @items = items
    fund_ids = @funds.map(&:id)
    # Active attachments only: a detached pack runs nothing, so it is not a column (H16)
    scoped = fund_packs.active.where(fund_id: fund_ids).includes(:compliance_pack, :compliance_pack_version)
    @fund_packs = scoped.group_by(&:fund_id)
    # One column per pack that is attached to at least one fund in the grid, by name
    @packs = scoped.map(&:compliance_pack).uniq.sort_by(&:name)
    @open_counts = items.open_items.where(fund_id: fund_ids).group(:fund_id).count
    @outcomes_by_fp = latest_outcomes(scoped.map(&:id))
  end

  def pack_for(fund, pack)
    (@fund_packs[fund.id] || []).detect { |fp| fp.compliance_pack_id == pack.id }
  end

  def monitored?(fund)
    @fund_packs[fund.id].present?
  end

  # { "breach" => 2, "needs_review" => 1, ... } for one attachment's latest result per check
  def outcomes_for(fund_pack)
    @outcomes_by_fp[fund_pack.id] || {}
  end

  # Stats cards — totals of the rows shown
  def stats
    @stats ||= begin
      totals = Hash.new(0)
      @outcomes_by_fp.each_value { |h| h.each { |o, n| totals[o] += n } }
      monitored = @funds.select { |f| monitored?(f) }
      {
        funds: @funds.size, monitored: monitored.size,
        breach: totals["breach"], needs_review: totals["needs_review"], could_not_check: totals["could_not_check"],
        overdue: @items.open_items.where(fund_id: @funds.map(&:id)).where(fix_by: ...Time.zone.today).count,
        stale: stale_count(monitored)
      }
    end
  end

  private

  # Same rule as ComplianceRun.stale? (no successful run, or the last one > 26 h ago), in one grouped
  # query for all funds instead of one run row per fund
  def stale_count(monitored, now: Time.current)
    return 0 if monitored.empty?

    last = ComplianceRun.succeeded.where(fund_id: monitored.map(&:id)).group(:fund_id).maximum(:finished_at)
    monitored.count { |f| last[f.id].nil? || (now - last[f.id]) > ComplianceRun::STALE_AFTER }
  end

  # Latest result per (attachment, check) — highest id, superseded ignored (R42), as each fund's
  # Compliance tab shows them — counted by outcome per attachment
  def latest_outcomes(fp_ids)
    return {} if fp_ids.empty?

    latest_ids = ComplianceResult.where(fund_compliance_pack_id: fp_ids, superseded_reason: nil)
                                 .group(:fund_compliance_pack_id, :check_key).maximum(:id).values
    ComplianceResult.where(id: latest_ids).group(:fund_compliance_pack_id, :outcome).count
                    .each_with_object({}) { |((fp_id, outcome), n), h| (h[fp_id] ||= {})[outcome] = n }
  end
end
