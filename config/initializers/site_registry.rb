# frozen_string_literal: true

# Fail the boot on a bad region configuration, rather than one user's region switch hours later.
#
# SITES and CURRENT_SITE are only read on the cross-region hand-off path, which a given
# deployment might not exercise for days. Before this check, a malformed SITES surfaced as a
# 500 inside UsersController#cross_site_link (nil + String), and a CURRENT_SITE matching no key
# surfaced as "Invalid or expired link" on every switch - both long after the deploy that caused
# them, and neither pointing at the setting. A boot that refuses to start is noisy in exactly
# the right place: the deploy.
#
# after_initialize, not an eager block, so dotenv has loaded the region's .env file by now.
Rails.application.config.after_initialize do
  SiteRegistry.validate!
end
