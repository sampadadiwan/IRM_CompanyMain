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
    user.entity_id == record.entity_id
  end

  def create?
    false
  end

  def compare_ckyc_kra?
    user.entity_id == record.entity_id
  end

  def generate_new?
    user.entity_id == record.entity_id
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
