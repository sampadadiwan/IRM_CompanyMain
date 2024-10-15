class ImportUploadPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(entity_id: user.entity_id).or(scope.where(user_id: user.id))
    end
  end

  def index?
    user.enable_import_uploads
  end

  def show?
    user.enable_import_uploads &&
      (
        owner_policy.permissioned_employee? ||
        (owner_policy.respond_to?(:import?) && owner_policy.import?)
      )
  end

  def create?
    user.enable_import_uploads &&
      (
        Pundit.policy(user, record.owner).permissioned_employee? ||
        (owner_policy.respond_to?(:import?) && owner_policy.import?)
      )
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

  def delete_data?
    update?
  end

  def owner_policy
    @owner_policy ||= Pundit.policy(user, record.owner)
    @owner_policy
  end
end
