# ⑩ Customer setup progress (E192, X91): CapHive super admins only. The page shows each firm's step
# count and next step — never funds, figures or people (R156).
class ComplianceOnboardingPolicy < ComplianceBasePolicy
  def index?
    super_admin?
  end

  # Every firm's setup row for a super admin; nothing for anyone else (verify_policy_scoped)
  class Scope < ApplicationPolicy::Scope
    def resolve
      user.has_cached_role?(:super) ? scope.all : scope.none
    end
  end
end
