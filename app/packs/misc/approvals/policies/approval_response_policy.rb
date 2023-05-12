class ApprovalResponsePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id).or(
        scope.where(response_entity_id: user.entity_id)
      )
    end
  end

  def index?
    true
  end

  def show?
    (user.entity_id == record.entity_id) || (user.entity_id == record.response_entity_id)
  end

  def create?
    (user.entity_id == record.entity_id)
  end

  def new?
    create?
  end

  def update?
    (user.entity_id == record.response_entity_id) && (record.approval.due_date >= Time.zone.today)
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  def approve?
    update?
  end
end
