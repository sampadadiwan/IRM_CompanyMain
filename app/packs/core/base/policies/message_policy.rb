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
    if belongs_to_entity?(user, record)
      true
    else
      record.owner &&
        (
          record.owner.entity_id == user.entity_id ||
          Pundit.policy(user, record.owner).show?
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
