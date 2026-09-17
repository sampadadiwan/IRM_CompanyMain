# `job` is filled in by marginalia's ActiveJob `around_perform` hook, which its railtie installs
# automatically -- that covers the ~134 ApplicationJob subclasses. `sidekiq_job` is filled in by
# the server middleware enabled below, which is the only way the handful of classes that
# `include Sidekiq::Worker` directly (they never go through ActiveJob) get annotated at all.
#
# Only one of the two is ever populated for a given query, and Marginalia::Comment#construct_comment
# skips blank components, so non-job queries are unaffected.
Marginalia::Comment.components = %i[controller action job sidekiq_job line]

# No-op outside a Sidekiq server process (Sidekiq.configure_server doesn't yield in the web
# process), so this is safe to run unconditionally from an initializer.
Marginalia::SidekiqInstrumentation.enable!
