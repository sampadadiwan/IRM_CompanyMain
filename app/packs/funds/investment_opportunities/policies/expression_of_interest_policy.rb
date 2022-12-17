class ExpressionOfInterestPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_cached_role?(:super)
        scope.all
      else
        scope.where(entity_id: user.entity_id).or(scope.where(eoi_entity_id: user.entity_id))
      end
    end
  end

  def index?
    true
  end

  def show?
    (user.entity_id == record.entity_id) ||
      (user.entity_id == record.eoi_entity_id)
  end

  def create?
    (user.entity_id == record.entity_id) ||
      (user.entity_id == record.eoi_entity_id)
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

  def generate_documentation?
    user.entity_id == record.entity_id && !record.esign_completed
  end

  def generate_esign_link?
    user.entity_id == record.entity_id &&
      record.esigns.count.zero? && !record.esign_completed
  end

  def destroy?
    update?
  end

  def approve?
    record.entity_id == user.entity_id
  end

  def allocate?
    record.entity_id == user.entity_id
  end

  def allocation_form?
    record.entity_id == user.entity_id
  end
end
