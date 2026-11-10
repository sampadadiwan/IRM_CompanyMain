# Ops tasks for "two-factor required for support and super" (OWASP 2026-11 M8).
# openspec/changes/archive/2026-11-10-require-2fa-privileged-roles — design card ⑧, lld.md "Configuration and Rollout".
#
# Run on EACH region's box (IN and US are independent servers):
#
#   bin/rails two_factor_required:report                          # read-only, counts only
#   bin/rails two_factor_required:end_unverified_access           # dry run: how many would be ended
#   bin/rails two_factor_required:end_unverified_access EXECUTE=1 # end their remembered access
#
# The rule is on from the deploy (user decision 2026-11-09, no enforcement date). Roll-out order: tell the few
# support / super users before the deploy → deploy → end_unverified_access (dry run, then EXECUTE=1 if it names
# anyone) so a remembered session can't skip set-up → report until it shows 0.
#
# Both tasks print counts only — never names, emails or ids.
namespace :two_factor_required do
  # Shared by both tasks: users without a verified method (2FA off, or on with no method stored)
  unverified_condition = lambda do
    ["users.two_factor_enabled = ? OR users.two_factor_mode IS NULL OR users.two_factor_mode = ''", false]
  end

  # The region, first line of every run
  print_header = lambda do
    puts "Region: #{SiteRegistry.current_code || 'unknown'} · two-factor required for: " \
         "#{RequiredTwoFactor::REQUIRED_2FA_ROLES.join(', ')} (from the deploy)"
  end

  desc "Counts per required role of active users with / without a verified two-factor method (read-only)"
  task report: :environment do
    print_header.call
    roles = RequiredTwoFactor::REQUIRED_2FA_ROLES.map(&:to_s)

    # H7 — every count is one grouped SQL aggregate; no user rows are loaded
    in_roles = User.active.joins(:roles).where(roles: { name: roles }).unscope(:order)
    active = in_roles.group("roles.name").distinct.count("users.id")
    without = in_roles.where(unverified_condition.call).group("roles.name").distinct.count("users.id")
    # Of those without, how many signed in during the last 90 days (they will meet set-up soonest)
    recent = in_roles.where(unverified_condition.call).where(users: { current_sign_in_at: 90.days.ago.. })
                     .group("roles.name").distinct.count("users.id")

    # One line per required role, in REQUIRED_2FA_ROLES order (E29 prints zeros)
    roles.each do |role|
      total = active.fetch(role, 0)
      missing = without.fetch(role, 0)
      puts "#{role}: #{total} active, #{total - missing} with a verified method, #{missing} without " \
           "(#{recent.fetch(role, 0)} of them signed in within 90 days)"
    end

    # A support user may also hold super, so people are counted once here
    puts "Distinct people without a verified method: #{in_roles.where(unverified_condition.call).distinct.count('users.id')}"

    # The privileged role the rule deliberately leaves out (user decision 2026-11-09), for reference
    admins = User.active.company_admins.unscope(:order)
    puts "company_admin: not required (#{admins.distinct.count('users.id')} active, " \
         "#{admins.where(two_factor_enabled: true).distinct.count('users.id')} with two-factor on)"
  end

  desc "End remember-me cookies and website-made tokens of support / super users still without two-factor (dry run unless EXECUTE=1)"
  task end_unverified_access: :environment do
    execute = ENV["EXECUTE"] == "1"
    print_header.call

    # Required roles, active, without a verified method — selected in SQL, deduplicated in SQL
    ids = User.active.joins(:roles).where(roles: { name: RequiredTwoFactor::REQUIRED_2FA_ROLES.map(&:to_s) })
              .where(unverified_condition.call).unscope(:order).distinct.pluck(:id)

    # E27 — the dry run only counts
    unless execute
      puts "Would end access for #{ids.size} users (run again with EXECUTE=1 to do it)"
      next
    end

    # H8 — per user: the remember-me cookie stops working (expire_all_remember_me_on_sign_out is on,
    # so forget_me! clears remember_created_at), and every live token made from the website is revoked.
    # The current web session is not touched (design D8: no forced sign-out); it lapses after 60 idle
    # minutes and the next sign-in meets set-up.
    User.where(id: ids).find_each do |user|
      ActiveRecord::Base.connected_to(role: :writing) do
        user.forget_me!
        # Profile › API tokens
        ApiToken.where(user_id: user.id, revoked_at: nil).find_each(&:revoke!)
        # MCP / OAuth clients and the Outlook / Gmail add-ins (MailAddinToken mints Doorkeeper tokens)
        Doorkeeper::AccessToken.where(resource_owner_id: user.id, revoked_at: nil).find_each(&:revoke)
      end
    end
    puts "Ended access for #{ids.size} users"
  end
end
