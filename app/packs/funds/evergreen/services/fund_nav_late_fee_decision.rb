# The approver's choice on a draft's late management fee (R9.13–R9.15): include it in this NAV's payable,
# or exclude it with a reason — for the whole amount still undecided. "clear" removes this draft's
# decisions (Change decision). The draft is then rebuilt, so the payable comes from FundNavBuilder alone.
# Worked examples H106, H107, E334, E335, X204, X206 —
# openspec/changes/archive/2026-10-11-evergreen-late-management-fees/design.md#⑤-decision
class FundNavLateFeeDecision < Trailblazer::Operation
  CHOICES = %w[include exclude clear].freeze
  REASON_MAX = 255

  step :check
  step :decide

  def check(ctx, fund_nav:, choice:, reason:, current_user:, **)
    reason = reason.to_s.strip
    ctx[:errors] = if fund_nav.approved? then "This NAV is already approved" # X206
                   elsif !current_user.has_cached_role?(:approver) then "Only an approver can decide a late fee"
                   elsif CHOICES.exclude?(choice.to_s) then "Choose Include or Exclude"
                   elsif choice == "exclude" && reason.empty? then "Give a reason for excluding the late fee" # X204
                   elsif reason.length > REASON_MAX then "Keep the reason to #{REASON_MAX} characters"
                   end
    ctx[:reason] = reason
    ctx[:errors].nil?
  end

  def decide(ctx, fund_nav:, choice:, current_user:, reason:, **)
    ActiveRecord::Base.transaction do
      fund_nav.lock!
      record(ctx, fund_nav, choice, ctx[:reason], current_user)
      raise ActiveRecord::Rollback if ctx[:errors]

      # One place computes the payable: rebuild the date's drafts with the decision in place (H106, E335)
      built = FundNavBuilder.call(fund: fund_nav.fund, nav_date: fund_nav.nav_date, current_user:)
      unless built.success?
        ctx[:errors] = built[:errors]
        raise ActiveRecord::Rollback
      end
    end
    ctx[:errors].nil?
  end

  private

  def record(ctx, fund_nav, choice, reason, user)
    if choice == "clear"
      # E335: Change decision — the approver decides again on the whole late amount
      fund_nav.audit_comment = "Late fee decisions cleared by #{user.full_name}"
      return fund_nav.update!(late_fee_decisions: nil)
    end

    # Re-read under the lock, so a double click can't record the same amount twice (E334: only what is new)
    late = EvergreenLateFees.call(fund_nav.fund, fund_nav.unit_type, fund_nav.nav_date, draft: fund_nav)
    amount = late.outstanding_cents
    return ctx[:errors] = "Nothing left to decide" unless amount.positive?

    money = Money.new(amount, fund_nav.fund.currency).format
    fund_nav.audit_comment = "Late management fee #{money} #{choice == 'include' ? 'included' : 'excluded'} by #{user.full_name}" \
                             "#{": #{reason}" if reason.present?}"
    fund_nav.update!(late_fee_decisions: fund_nav.late_fee_decisions_list + [{ "amount_cents" => amount.to_s, "choice" => choice,
                                                                               "reason" => reason.presence, "user_id" => user.id,
                                                                               "decided_at" => Time.current.iso8601 }])
  end
end
