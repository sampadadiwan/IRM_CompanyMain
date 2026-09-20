# Ambient state for whatever is executing right now — a request, or a job.
#
# It holds exactly one thing: *who is acting*. Resist adding more. The value of
# this object is that a reader can tell at a glance what ambient state exists;
# an entity, a fund or a locale bolted on here turns it into a god object whose
# contents nobody can predict.
#
# Set in requests by WithAuthentication#set_current_user, and carried across the
# process boundary into jobs by ApplicationJob (see the comment there for why
# that is needed at all).
#
# Lifecycle is Rails', not ours: the executor calls
# ActiveSupport::CurrentAttributes.clear_all on both `to_run` and `to_complete`
# (activesupport/railtie.rb), and ActiveJob wraps every perform in
# `app.reloader.wrap` (activejob/railtie.rb), so a value cannot leak from one
# request or job to the next on a reused thread.
class Current < ActiveSupport::CurrentAttributes
  attribute :user
end
