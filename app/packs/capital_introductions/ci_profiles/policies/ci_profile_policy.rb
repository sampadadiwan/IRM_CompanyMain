class CiProfilePolicy < FundBasePolicy
  def index?
    true
  end

  def show?
    permissioned_employee? ||
      permissioned_investor?
  end

  def create?
    belongs_to_entity?(user, record)
  end

  def new?
    permissioned_employee?(:create)
  end

  def update?
    permissioned_employee?(:update)
  end

  def edit?
    update?
  end

  def destroy?
    Rails.env.test? ? permissioned_employee?(:destroy) : super_user?
  end
end
