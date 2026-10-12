# Returns an approved NAV to draft — only when no confirmed dealing date was priced at it.
# Reverses any crystallisation (entries deleted, high-water mark restored).
# Worked examples E9, E44, X9 — openspec/changes/open-ended-funds/design.md#worked-examples
class FundNavReopen < Trailblazer::Operation
  step :check
  step :reopen

  def check(ctx, fund_nav:, current_user:, **)
    ctx[:errors] = if !fund_nav.approved? then "Only an approved NAV can be reopened"
                   elsif !current_user.has_cached_role?(:approver) then "Only an approver can reopen a NAV"
                   elsif fund_nav.used_by_dealing? then "Used by #{EvergreenLabels.lower(EvergreenLabels.t(:transaction_date, fund: fund_nav.fund))} #{I18n.l(fund_nav.used_by_dealing_date.date, format: :day_month_year)} — cannot reopen"
                   end
    ctx[:errors].nil?
  end

  def reopen(ctx, fund_nav:, **)
    reopened = ActiveRecord::Base.transaction do
      fund_nav.lock!
      # Re-check under the lock: a confirm may have priced at this NAV since the check (review finding)
      next false if !fund_nav.approved? || fund_nav.used_by_dealing?

      Crystalliser.reverse(fund_nav) if fund_nav.crystallised
      fund_nav.update!(status: "draft", approved_by: nil, approved_at: nil)
      true
    end
    ctx[:errors] = "This NAV was just used to price a #{EvergreenLabels.lower(EvergreenLabels.t(:transaction_date, fund: fund_nav.fund))} — it can no longer be reopened" unless reopened
    reopened
  end
end
