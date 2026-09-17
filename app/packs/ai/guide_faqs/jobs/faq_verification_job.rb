# frozen_string_literal: true

# Nightly: flags published FAQs whose quoted paths no longer route, whose guide links broke, or
# that have not been verified for FaqEntry::VERIFY_EVERY. Flagged entries stay published and show
# under "Needs verification" in FAQ Manager.
class FaqVerificationJob < ApplicationJob
  queue_as :low

  def perform
    FaqEntry.published.find_each(&:refresh_verification!)
  end
end
