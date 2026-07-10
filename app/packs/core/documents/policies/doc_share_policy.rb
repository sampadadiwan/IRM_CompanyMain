class DocSharePolicy < ApplicationPolicy
  class Scope < Scope
    # NOTE: Be explicit about which records you allow access to!
    def resolve
      if user.has_cached_role?(:company_admin)
        # SECURITY (finding M3): scope to the admin's OWN entity's documents. Previously returned
        # scope.all, exposing every other entity's doc-share metadata (recipient emails, view
        # counts, document ids) in the index to any company admin.
        scope.joins(:document).where(documents: { entity_id: user.entity_id })
      else
        scope.where(document_id: user.documents.pluck(:id))
      end
    end
  end

  def view?
    record.present? && record.email_sent
  end

  def show?
    DocumentPolicy.new(user, record.document).update?
  end

  def create?
    DocumentPolicy.new(user, record.document).update?
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    create?
  end
end
