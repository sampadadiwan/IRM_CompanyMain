# A user lists, creates and revokes only their own API tokens, and only from a website session:
# a token can never be used to make or manage tokens (X19 X20). funds-json-api-hardening card ①.
class ApiTokenPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.where(user_id: user.id)
    end
  end

  def index?
    true
  end

  # M6 (OWASP 2026-11): not while CapHive support is signed in as this user ("Login as"). A token made then would
  # outlive the support access (90 days), act in the client's name with no "impersonated by" trail, and survive the
  # support mapping being switched off. UsersController#cross_site_link already refuses this case (M5-1).
  def create?
    user.support_user_id.blank?
  end

  def destroy?
    record.user_id == user.id
  end
end
