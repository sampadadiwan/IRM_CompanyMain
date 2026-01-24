# Pundit policy for InvestmentCriteriaTemplate authorization.
#
# Enforces entity-based access control where users can view, edit, and delete
# templates belonging to their entity. All authenticated users can create new templates.
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

  # Allows viewing only if the user belongs to the same entity.
  #
  # @return [Boolean] true if user belongs to the same entity
  def show?
    record.entity_id == user.entity_id
  end

  # Allows preview only if the user belongs to the same entity.
  #
  # @return [Boolean] true if user belongs to the same entity
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

  # Allows editing only if the user belongs to same entity.
  #
  # @return [Boolean] true if user belongs to the same entity
  def edit?
    record.entity_id == user.entity_id
  end

  # Allows updating only if the user belongs to same entity.
  #
  # @return [Boolean] true if user belongs to the same entity
  def update?
    record.entity_id == user.entity_id
  end

  # Allows deletion only if the user belongs to same entity.
  #
  # @return [Boolean] true if user belongs to the same entity
  def destroy?
    record.entity_id == user.entity_id
  end

  # Scope class for filtering templates to those belonging to the user's entity.
  class Scope < Scope
    # Resolves the scope to only include templates belonging to the user's entity.
    #
    # @return [ActiveRecord::Relation<InvestmentCriteriaTemplate>] entity templates
    def resolve
      scope.where(entity_id: user.entity_id)
    end
  end
end
