# frozen_string_literal: true

# Base mailer for all support agent emails.
# Includes shared email styling helpers (sa_banner, sa_callout, etc.)
class SupportAgentBaseMailer < ApplicationMailer
  helper SupportAgentEmailHelper
  helper CurrencyHelper
end
