class ExpressionOfInterestPolicy < IoBasePolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:company_admin) && user.entity_type == "Investment Fund"
        scope.where(entity_id: user.entity_id)
      elsif user.curr_role == "employee" && user.entity_type == "Investment Fund"
        scope.for_employee(user)
      else
        scope.for_investor(user)
      end
    end
  end

  def index?
    true
  end

  def show?
    permissioned_employee? ||
      permissioned_investor?
  end

  def new?
    create?
  end

  def update?
    permissioned_employee?(:update)
  end

  def edit?
    update?
  end

  def generate_documentation?
    update? && !record.esign_completed
  end

  def generate_esign_link?
    update? &&
      record.esigns.count.zero? && !record.esign_completed
  end

  def destroy?
    permissioned_employee?(:destroy)
  end

  def approve?
    update?
  end

  def allocate?
    update?
  end

  def allocation_form?
    update?
  end
end
