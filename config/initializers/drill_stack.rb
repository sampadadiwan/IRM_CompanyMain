# frozen_string_literal: true

# On a DR DRILL stack - and only there (DR_DRILL_STACK, written only into a drill branch's .env) -
# stop every outgoing channel so the drill copy never reaches a user: email, WhatsApp, SMS and
# push. Timed jobs are kept off in config/initializers/sidekiq.rb. On the real app this does
# nothing. (openspec fix-dr-drill-contacts-users)
require Rails.root.join("lib/drill_stack")

Rails.application.config.after_initialize do
  # after_initialize: ActionMailer and Net::HTTP are loaded by then
  DrillStack.activate!
end
