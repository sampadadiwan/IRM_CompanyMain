# frozen_string_literal: true

# @description Authorization policy for NdaConfig. Only GP/admin users with update
#   rights on the owner (e.g., a Data Room folder) may access NDA configuration.
#
# Changed: Renamed from FolderNdaConfigPolicy, moved from core/folders/ to core/nda_configs/.
# Why: Policy now references the polymorphic owner instead of a direct folder association.
#
# @see NdaConfig
# @see FolderPolicy#update?
class NdaConfigPolicy < ApplicationPolicy
  # @return [Boolean]
  def new?
    manageable?
  end

  # @return [Boolean]
  def create?
    manageable?
  end

  # @return [Boolean]
  def edit?
    manageable?
  end

  # @return [Boolean]
  def update?
    manageable?
  end

  private

  # @return [Boolean] Whether the user is a GP/admin with management rights on the owner.
  # Changed: record.folder → record.owner with type-based dispatch.
  # Why: NdaConfig is polymorphic — each owner type has its own authorization rules.
  def manageable?
    user.curr_role_employee? && owner_manageable?
  end

  # @return [Boolean] Whether the user has management rights on the specific owner type.
  #   Each owner type defines its own authorization logic. New owner types (e.g.,
  #   InvestmentOpportunity) add a branch here with their specific policy checks.
  def owner_manageable?
    case record.owner
    when Folder
      record.owner.in_data_room? && FolderPolicy.new(user, record.owner).update?
    else
      false
    end
  end
end
