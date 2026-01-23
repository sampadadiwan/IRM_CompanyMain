# Pundit policy for InvestmentCriteriaTemplate authorization.
#
# Enforces owner-based access control where users can only view, edit, and delete
# their own templates. All authenticated users can create new templates.
#
# @see InvestmentCriteriaTemplate
# @see InvestmentCriteriaTemplatesController
class InvestmentCriteriaTemplatePolicy < ApplicationPolicy
  # Allows any authenticated user to view the template index.
  #
  # @return [Boolean] true for all authenticated users
  def index?
    true
  end

  # Allows viewing only if the user owns the template.
  #
  # @return [Boolean] true if user is the template owner
  def show?
    record.created_by_user_id == user.id
  end

  # Allows preview only if the user owns the template.
  #
  # @return [Boolean] true if user is the template owner
  def preview?
    show?
  end

  # Allows any authenticated user to access the new template form.
  #
  # @return [Boolean] true for all authenticated users
  def new?
    true
  end

  # Allows any authenticated user to create templates.
  #
  # @return [Boolean] true for all authenticated users
  def create?
    true
  end

  # Allows editing only if the user owns the template.
  #
  # @return [Boolean] true if user is the template owner
  def edit?
    record.created_by_user_id == user.id
  end

  # Allows updating only if the user owns the template.
  #
  # @return [Boolean] true if user is the template owner
  def update?
    record.created_by_user_id == user.id
  end

  # Allows deletion only if the user owns the template.
  #
  # @return [Boolean] true if user is the template owner
  def destroy?
    record.created_by_user_id == user.id
  end

  # Scope class for filtering templates to those owned by the current user.
  class Scope < Scope
    # Resolves the scope to only include templates created by the current user.
    #
    # @return [ActiveRecord::Relation<InvestmentCriteriaTemplate>] user-owned templates
    def resolve
      scope.where(created_by_user_id: user.id)
    end
  end
end
