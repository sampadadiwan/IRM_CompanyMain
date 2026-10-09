# Unlocking allocation runs can change the data behind locked statements (accepted v1 risk). This
# finds the locked statement sets an unlock touches, and after the unlock returns them to Draft
# (frozen copy kept until they are locked again) and tells the fund's Fund accounting users once.
# When nothing is affected, AllocationRunsController behaves exactly as before.
# Worked examples H16, H17, E8, E15, E23 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementUnlockGuard
  RECIPIENT_TAG = "FundAccounting".freeze

  # Locked statement sets overlapping the period, or all of the fund's with no dates (Unlock all)
  def self.affected(fund, start_date = nil, end_date = nil)
    scope = FinancialStatement.locked.where(fund_id: fund.id)
    # Unlock: sets overlapping the clicked run's period; Unlock all: every locked set
    start_date && end_date ? scope.overlapping(start_date, end_date) : scope
  end

  # @return [Integer] how many sets went back to Draft (0: nothing sent)
  def self.demote!(statements, user:)
    statements = statements.to_a
    # E8: nothing locked overlaps — no change, no notification
    return 0 if statements.empty?

    # Back to Draft; frozen_data is kept (it is what was published)
    FinancialStatement.where(id: statements.map(&:id)).update_all(status: "draft", locked_at: nil, locked_by_id: nil, updated_at: Time.current)
    # Their statements runs too (Unlock all already did; Unlock may not reach a one-day run)
    statements.filter_map(&:statements_allocation_run).each { |run| run.update_column(:locked, false) }
    notify(statements, user)
    statements.size
  end

  # One notification per unlock request, listing every demoted set (E15)
  def self.notify(statements, user)
    fund = statements.first.fund
    sorted = statements.sort_by(&:end_date)
    # Screen-format labels for the in-app message; ISO dates for the email, which renders its own format
    periods = sorted.map(&:period_label)
    period_dates = sorted.map { |s| [s.start_date.iso8601, s.end_date.iso8601] }
    # One delivery per recipient, listing every demoted set
    recipients(fund).each do |recipient|
      FinancialStatementNotifier.with(record: fund, entity_id: fund.entity_id, unlocked_by: user.full_name,
                                      periods:, period_dates:, statement_ids: statements.map(&:id)).deliver_later(recipient)
    end
  end

  # Active users of the fund's entity tagged "FundAccounting" who can see the fund
  def self.recipients(fund)
    # Tag match is a LIKE on users.tag_list (as for the Kpi / Tasks tags); then the fund policy
    User.where(entity_id: fund.entity_id, active: true).with_tag(RECIPIENT_TAG).select do |recipient|
      Pundit.policy(recipient, fund).show?
    end
  end
end
