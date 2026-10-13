# Shared rules for every evergreen record: access is decided on the record's fund through FundPolicy
# (so existing fund access rights apply unchanged), and nothing is allowed unless the entity has
# evergreen funds switched on. Approvals need the existing :approver role, like CapitalCallPolicy#approve?.
# Worked examples E47, X19 — openspec/changes/open-ended-funds/design.md#worked-examples
class EvergreenBasePolicy < FundBasePolicy
  def index?
    user.enable_funds
  end

  def show?
    entity_enabled? && (fund_employee?(:read) || fund_investor?)
  end

  def create?
    entity_enabled? && fund_employee?(:update)
  end

  def new?
    create?
  end

  def update?
    entity_enabled? && fund_employee?(:update)
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end

  protected

  def fund
    record.respond_to?(:fund) ? record.fund : record
  end

  def entity_enabled?
    fund&.entity&.permissions&.enable_evergreen_funds? || false
  end

  # A GP user of the fund's entity with the fund access right (company admins see everything)
  def fund_employee?(perm)
    return false if user.curr_role == "investor"

    policy = FundPolicy.new(user, fund)
    perm == :update ? policy.update? : policy.show?
  end

  # An investor user with approved access to the fund
  def fund_investor?
    user.curr_role == "investor" && FundPolicy.new(user, fund).show?
  end

  def approver?
    user.has_cached_role?(:approver)
  end
end
