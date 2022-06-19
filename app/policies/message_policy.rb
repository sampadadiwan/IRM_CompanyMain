class MessagePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      else
        scope.where(entity_id: user.entity_id)
      end
    end
  end

  def index?
    true
  end

  def show?
    create?
  end

  def mark_as_task?
    create?
  end

  def create?
    Rails.logger.debug record.to_json
    if user.entity_id == record.entity_id
      true
    else
      record.owner &&
        (
          record.owner.entity_id == user.entity_id ||
          (record.owner_type == "Interest" && record.owner.interest_entity_id == user.entity_id)
        )
    end
  end

  def new?
    create?
  end

  def update?
    create?
  end

  def edit?
    create?
  end

  def destroy?
    create?
  end
end
