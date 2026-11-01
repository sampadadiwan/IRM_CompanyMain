# frozen_string_literal: true

# The one environment switch that turns CSRF verification off, and the boot guard that keeps it
# out of real deployments (docs/security/security_review_2026_10.md, L4).
#
# SKIP_AUTHENTICITY_TOKEN=true exists for local ngrok work only (a cross-domain login through the
# tunnel, docs/modules/ai/mcp_server/technical_design.md). It used to be honoured in every
# environment, and VULN_SCAN=true switched CSRF off for every controller too. Now:
#   * the skip is honoured only in development (L4-1: test, staging and production ignore it);
#   * production and staging refuse to boot with it set (L4-1);
#   * VULN_SCAN keeps only its exception-mail meaning (config/initializers/exception_notification.rb).
#
# Defined here rather than under lib/ because the boot guard below runs during initialization,
# before autoloaded constants may be referenced.
module CsrfSwitches
  # Environments that must never run with CSRF verification switched off
  GUARDED_ENVS = %w[production staging].freeze

  module_function

  # Whether the environment asks for the skip at all
  def skip_requested?(env = ENV)
    env["SKIP_AUTHENTICITY_TOKEN"] == "true"
  end

  # L4-H / L4-1 — whether a request may skip CSRF verification: development only
  def skip_verification?(rails_env: Rails.env, env: ENV)
    # Asked for, and only on a developer's machine
    skip_requested?(env) && rails_env.to_s == "development"
  end

  # L4-1 — refuses to boot a guarded environment with the skip set
  def guard!(rails_env: Rails.env, env: ENV)
    # Nothing to refuse when the switch is not set, or outside production/staging
    return unless skip_requested?(env) && GUARDED_ENVS.include?(rails_env.to_s)

    raise "SKIP_AUTHENTICITY_TOKEN=true is refused in #{rails_env}: it disables CSRF protection. " \
          "Unset it (it is for local ngrok development only)."
  end
end

CsrfSwitches.guard!
