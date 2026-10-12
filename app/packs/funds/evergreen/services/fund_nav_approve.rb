# Approval of a draft NAV. Rules (enforced here, not only in the view):
# - the approver must hold the :approver role; who prepared or overrode it doesn't matter (review fix 1,
#   10 Oct 2026) — the audit comment records when the approver also prepared / overrode it;
# - a stale draft (its inputs changed after drafting) is refused until recalculated (review fix 2,
#   10 Oct 2026): approving it would fix a price built from out-of-date figures;
# - a draft whose management fee isn't accrued up to its date is refused (R9.2, X208), and so is one
#   with a late management fee still undecided (R9.13, X207).
# On a class's crystallisation date the accrued performance fee is crystallised and the mark moves up.
# Worked examples H6, H30, E43, X8 — openspec/changes/open-ended-funds/design.md#worked-examples
class FundNavApprove < Trailblazer::Operation
  step :check
  step :approve

  # Shown on the refused request and as the disabled Approve button's reason (review fix 2)
  STALE_MESSAGE = "Inputs changed since drafted — recalculate before approving".freeze

  def check(ctx, fund_nav:, current_user:, **)
    ctx[:errors] = if fund_nav.approved? then "This NAV is already approved"
                   elsif !current_user.has_cached_role?(:approver) then "Only an approver can approve a NAV"
                   # Review fix 2: a stale draft would fix a price from out-of-date figures — recalculate first
                   else self.class.block_reason(fund_nav)
                   end
    ctx[:errors].nil?
  end

  # Why a draft can't be approved yet, or nil — also the NAV page's disabled-Approve reason, so the
  # button and a direct request give the same answer
  def self.block_reason(fund_nav)
    # Review fix 2: a stale draft would fix a price from out-of-date figures — recalculate first
    return STALE_MESSAGE if fund_nav.stale?

    # R9.2 (X208): the management fee must be accrued up to the NAV date (exempt: uploaded, 0 %, no units)
    accrual = EvergreenFeeCheck.accrual_message(fund_nav)
    return accrual if accrual

    # R9.13 (X207): a late management fee on the draft needs the approver's Include / Exclude first.
    # Uploaded NAVs carry no fee lines, so they never hold a late amount (E330)
    return nil if fund_nav.uploaded?

    late = EvergreenLateFees.call(fund_nav.fund, fund_nav.unit_type, fund_nav.nav_date, draft: fund_nav)
    "Decide the late management fee for class #{fund_nav.unit_type} first" if late.outstanding_cents.positive?
  end

  def approve(ctx, fund_nav:, current_user:, **)
    approved = ActiveRecord::Base.transaction do
      fund_nav.lock!
      # Re-check under the lock: two approvers clicking at once must not crystallise twice
      next false if fund_nav.approved?

      # ...and the refusals, in case the inputs changed between the check and the lock
      if (reason = self.class.block_reason(fund_nav))
        ctx[:block] = reason
        next false
      end

      # Recorded in the audit trail; an approver who also overrode lines may approve, and the trail says so
      overrode = fund_nav.overrides_hash.select { |_, o| o["user_id"].to_i == current_user.id }.keys
      # Small funds: the approver may also be the preparer — allowed, and the trail says so
      notes = []
      notes << "approver also prepared this NAV" if fund_nav.prepared_by_id == current_user.id
      notes << "approver also overrode #{overrode.map { |l| l.humanize.downcase }.join(', ')}" if overrode.any?
      fund_nav.audit_comment = "Approved#{" — #{notes.join('; ')}" if notes.any?}"
      fund_nav.update!(status: "approved", approved_by: current_user, approved_at: Time.current)
      Crystalliser.call(fund_nav:)
      true
    end
    ctx[:errors] = ctx[:block] || "This NAV is already approved" unless approved
    # Preparer + Fund ops, investors' NAV update, dealing dates now ready (§ Notifications)
    EvergreenAlerts.nav_approved(fund_nav) if approved
    approved
  end
end
