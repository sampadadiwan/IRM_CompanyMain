class ApprovalResponsePolicy < ApprovalBasePolicy
  class Scope < Scope
    def resolve
      if user.entity_type == "Group Company"
        scope.where(entity_id: user.entity.child_ids)
      else
        scope.where(entity_id: user.entity_id).or(
          scope.where(response_entity_id: user.entity_id)
        )
      end
    end
  end

  def index?
    user.enable_approvals
  end

  def show?
    user.enable_approvals &&
      (permissioned_employee? || permissioned_investor?)
  end

  def create?
    permissioned_employee?
  end

  def new?
    create?
  end

  def update?
    (create? || permissioned_investor?) && record.approval.due_date >= Time.zone.today
  end

  def edit?
    update?
  end

  def preview?
    permissioned_employee?
  end

  def destroy?
    false
  end

  def approve?
    permissioned_investor? && (record.approval.due_date >= Time.zone.today)
  end
end
