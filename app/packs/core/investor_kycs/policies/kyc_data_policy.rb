class KycDataPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if %i[employee].include? user.curr_role.to_sym
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
    belongs_to_entity?(user, record)
  end

  def create?
    false
  end

  def compare_ckyc_kra?
    belongs_to_entity?(user, record)
  end

  def generate_new?
    belongs_to_entity?(user, record)
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    false
  end

  def destroy?
    false
  end
end
