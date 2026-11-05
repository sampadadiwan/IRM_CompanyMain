# frozen_string_literal: true

# config.yjit = true is a silent no-op on a Ruby built without YJIT (rustc missing when it was
# compiled) — which is exactly how a whole cucumber run once went out without YJIT unnoticed.
#
# - test: refuse to boot. Tests are meant to run under YJIT (parity with staging/production);
#   a run on the wrong Ruby must fail at once, not pass on a different runtime.
# - elsewhere: log a warning (a server on the wrong Ruby keeps serving).
# YJIT=0 opts out explicitly (config.yjit is then false and this check is skipped).
Rails.application.config.after_initialize do
  next unless Rails.application.config.yjit
  # after_initialize runs before Rails' own :enable_yjit initializer, so check availability,
  # not RubyVM::YJIT.enabled? (which still reads false at this point).
  next if defined?(RubyVM::YJIT.enable)

  fix = "Dev machine: bin/setup-yjit #{RUBY_VERSION}  ·  server: cap <stage> yjit:enable  ·  " \
        "to run without YJIT on purpose: YJIT=0"
  message = "config.yjit is on but #{RUBY_DESCRIPTION} (#{RbConfig.ruby}) was built without YJIT. #{fix}"
  raise message if Rails.env.test?

  Rails.logger.warn(message)
end
