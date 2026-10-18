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

  def create?
    true
  end

  def destroy?
    record.user_id == user.id
  end
end
