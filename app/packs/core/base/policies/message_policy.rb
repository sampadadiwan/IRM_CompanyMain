class MessagePolicy < ApplicationPolicy
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
    belongs_to_entity?(user, record) || (record.owner &&
      (
        record.owner.entity_id == user.entity_id ||
        Pundit.policy(user, record.owner).show?
      ))
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
