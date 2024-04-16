class InvestorKycSebiDataPolicy < InvestorKycPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end

  def sub_categories?
    show?
  end

  def index?
    true
  end

  def show?
    belongs_to_entity?(user, record) && user.curr_role != "investor"
  end

  def create?
    belongs_to_entity?(user, record)
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    update?
  end

  def destroy?
    belongs_to_entity?(user, record) && company_admin_or_emp_crud?(user, record, :destroy)
  end
end
