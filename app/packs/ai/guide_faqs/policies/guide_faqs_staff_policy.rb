# frozen_string_literal: true

# Base policy for FAQ Manager screens: CapHive support and super users only.
#
# Checks the roles directly rather than User#support?, which is also true while a support user
# is impersonating a customer. Impersonation is for seeing the app as the customer does, and the
# FAQ Manager link must not appear (or 403) inside that session — same rule as InternalDocPolicy.
class GuideFaqsStaffPolicy < ApplicationPolicy
  %i[index? show? create? update? destroy?].each do |action|
    define_method(action) { staff? }
  end

  class Scope < BaseScope
    def resolve
      user.has_cached_role?(:support) || user.has_cached_role?(:super) ? scope.all : scope.none
    end
  end

  private

  def staff?
    user.present? && (user.has_cached_role?(:support) || user.has_cached_role?(:super))
  end
end
