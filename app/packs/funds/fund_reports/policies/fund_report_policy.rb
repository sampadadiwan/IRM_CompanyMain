class FundReportPolicy < FundBasePolicy
  def index?
    user.enable_funds
  end

  def show?
    permissioned_employee?
  end

  def regenerate?
    create?
  end

  def download_page?
    create?
  end

  def create?
    permissioned_employee?(:create)
  end

  def update?
    permissioned_employee?(:update)
  end

  def destroy?
    create?
  end
end
