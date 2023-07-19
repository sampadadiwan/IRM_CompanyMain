class ApprovalResponsePolicy < ApplicationPolicy
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
    true
  end

  def show?
    belongs_to_entity?(user, record) || (user.entity_id == record.response_entity_id)
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
    false
  end

  def approve?
    (user.entity_id == record.response_entity_id) && (record.approval.due_date >= Time.zone.today)
  end
end
