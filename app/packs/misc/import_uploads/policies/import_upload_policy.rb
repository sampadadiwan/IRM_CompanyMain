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
        owner_allows_import?
      )
  end

  def create?
    user.enable_import_uploads &&
      (
        Pundit.policy(user, record.owner).permissioned_employee? ||
        owner_allows_import?
      )
  end

  # Import types whose owner policy has its own, narrower predicate than the generic import?.
  # Without this an RM refused import_offers? could still upload an offers file to a sale, because
  # only import? (= import_interests? for RMs) was checked (security review 2026-10, H15 follow-up).
  TYPE_PREDICATES = {
    "Offer" => :import_offers?,
    "OfferDocs" => :import_offers?,
    "Interest" => :import_interests?
  }.freeze

  # Non-employee path: the owner's own import rule for this import type, else its generic import?
  def owner_allows_import?
    return false unless owner_policy.respond_to?(:import?)

    predicate = TYPE_PREDICATES[record.import_type.to_s]
    return owner_policy.public_send(predicate) if predicate && owner_policy.respond_to?(predicate)

    owner_policy.import?
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
