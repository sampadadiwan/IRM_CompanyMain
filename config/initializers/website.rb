# Host-gated static serving of the company website (public/website/) on the
# apex domain. See lib/middleware/website.rb for the full rationale and
# docs/modules/website/website_serving.md for the design.
require_relative "../../lib/middleware/website"

# Position 0: ahead of ActionDispatch::Static (so website content is only
# reachable through the host gate), the session store (no shared cookie for
# anonymous website visitors) and Log404s/Rack::Attack (apex scanner 404s
# can't poison the app's per-IP counters). The flip side — website requests
# also bypass Rack::Attack's blocklist/throttle — is an accepted trade-off:
# misses answer from a memoized in-memory 404 body and hits are plain static
# reads, so a banned scanner can't make puma do interesting work here, and
# production serves the apex from nginx anyway.
Rails.application.config.middleware.insert_before(0, Website)
