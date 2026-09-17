# Authorizes reads of WebsiteLead — inbound demo requests from the public site.
#
# Every other record in this app is reachable because the user belongs to its
# entity. A WebsiteLead has no entity: it is created by an anonymous visitor
# before any relationship exists. Tenancy therefore cannot gate it, and role is
# the only boundary available.
#
# Deny by default — ApplicationPolicy's index?/show? already return false, and
# nothing here widens beyond the two staff roles. There is deliberately no
# create?/update?/destroy?: the public endpoint bypasses Pundit entirely (it has
# no user), and the admin screens are read-only.
class WebsiteLeadPolicy < ApplicationPolicy
  def index?
    staff?
  end

  def show?
    staff?
  end

  private

  # The same roles that authorize the internal docs viewer and support
  # impersonation in UserPolicy#login_as?.
  #
  # Checks the roles directly rather than calling User#support?, which also
  # returns true while a support user is impersonating a customer. Impersonation
  # exists to see the app as the customer sees it; it must not carry CapHive's
  # inbound sales pipeline into that session.
  def staff?
    user.present? && (user.has_cached_role?(:support) || user.has_cached_role?(:super))
  end
end
