# Authorizes the internal marketing/commercial docs browser (InternalDocsController).
#
# Deliberately STRICTER than UserGuidePolicy: user guides are customer-facing,
# these documents hold pricing bands, GTM strategy and competitive analysis.
# Deny by default — ApplicationPolicy's index?/show? already return false, and
# nothing here widens beyond the two staff roles.
class InternalDocPolicy < ApplicationPolicy
  def index?
    staff?
  end

  def show?
    staff?
  end

  private

  # The same roles that authorize support impersonation in UserPolicy#login_as?.
  #
  # Note this checks the roles directly rather than calling User#support?, which
  # also returns true when support_user_id is present — i.e. while a support
  # user is impersonating a customer. Impersonation exists to see the app as the
  # customer sees it; it must not carry CapHive's commercial documents into that
  # session.
  def staff?
    user.present? && (user.has_cached_role?(:support) || user.has_cached_role?(:super))
  end
end
