class AdhaarEsignPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if %i[startup fund_manager].include? user.curr_role.to_sym
        scope.where(entity_id: user.entity_id)
      else
        scope.none
      end
    end
  end

  def index?
    true
  end

  def show?
    user.entity_id == record.entity_id
  end

  def create?
    false
  end

  def advisor?
    record.entity.advisor?(user)
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
    update?
  end

  # Only users who are part of this eSign can complete it
  def completed?
    record.owner.esigns.where(user_id: user.id).present?
  end
end
