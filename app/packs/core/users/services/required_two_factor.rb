# Who MUST use two-factor authentication (OWASP 2026-11 finding M8).
#
# REQUIRED_2FA_ROLES is the one place the rule's roles are named: CapHive staff only (support, super), by user
# decision 2026-11-09; adding company admins later is one line.
#
# The rule is on from the day it is deployed, in every region (user decision 2026-11-09: "there are very few support
# users and we can force it on day one"). There is no enforcement date, notice period or banner: a support or super
# user without a verified method is taken through set-up at their next sign-in, and Login as is refused until then.
# On deploy day ops runs `bin/rails two_factor_required:end_unverified_access` so remembered sessions can't skip it.
#
# Nothing here is stored per user. TwoFactorAuthenticatable#two_factor_required? reads the user's cached roles, and
# every sign-in door asks #two_factor_applies?.
#
# openspec/changes/archive/2026-11-10-require-2fa-privileged-roles — design card ①, decision D1 ("Changed during the build" C-day-one).
module RequiredTwoFactor
  # The roles that must use two-factor. Order matters only for #role_label: a support user switched into a client
  # also holds company_admin, and a user holding both support and super reads "Support" (E12).
  REQUIRED_2FA_ROLES = %i[support super].freeze

  class << self
    # The role that makes the user's two-factor required, for labels ("Support", "Super"); nil for anyone else
    # @param user [User]
    # @return [String, nil]
    def role_label(user)
      # The first required role the user holds, in REQUIRED_2FA_ROLES order
      role = REQUIRED_2FA_ROLES.find { |r| user.has_cached_role?(r) }
      role&.to_s&.titleize
    end
  end
end
