class FundReportPolicy < FundBasePolicy
  def index?
    true
  end

  def show?
    user.has_cached_role?(:company_admin)
  end

  def regenerate?
    create?
  end

  def download_page?
    create?
  end

  def create?
    user.has_cached_role?(:company_admin)
  end

  def destroy?
    create?
  end
end
