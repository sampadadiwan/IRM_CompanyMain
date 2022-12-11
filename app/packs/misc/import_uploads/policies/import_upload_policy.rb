class ImportUploadPolicy < ApplicationPolicy
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
    (user.entity_id == record.entity_id) ||
      permissioned_advisor?
  end

  def create?
    (user.entity_id == record.entity_id) ||
      permissioned_advisor?(:create)
  end

  def new?
    create?
  end

  def update?
    (user.entity_id == record.entity_id) ||
      permissioned_advisor?(:update)
  end

  def edit?
    update?
  end

  def destroy?
    update?
  end

  def permissioned_advisor?(perm = nil)
    if user.entity_id != record.entity_id && user.curr_role == "advisor"
      owner = record.owner
      db_owner ||= owner.class.for_advisor(user).includes(:access_rights).where("#{owner.class.table_name}.id=?", owner.id).first

      if perm
        db_owner.present? && db_owner.access_rights[0].permissions.set?(perm)
      else
        db_owner.present?
      end
    else
      false
    end
  end
end
