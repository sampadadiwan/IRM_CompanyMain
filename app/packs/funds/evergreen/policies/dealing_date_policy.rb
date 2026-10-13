# Dealing dates are GP-only: fund users see them; fund update rights confirm, undo, close and settle.
# Worked examples H17, H21, E33, X18 — openspec/changes/open-ended-funds/design.md#worked-examples
class DealingDatePolicy < EvergreenBasePolicy
  def show?
    entity_enabled? && fund_employee?(:read)
  end

  def confirm?
    update? && record.open?
  end

  def undo?
    update? && record.confirmed?
  end

  def close?
    update? && record.confirmed?
  end

  # § Dealing-date documents: anyone who can settle generates; only approvers approve & send
  def generate_documents?
    update? && record.confirmed?
  end

  def approve_documents?
    generate_documents? && approver?
  end
end
