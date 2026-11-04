# Where Digio's embeddable signing panel (SDK v11) is loaded from, and which mode to run it in.
#
# The SDK host is not the API host: DIGIO_BASE_URL is the API (e.g. https://ext.digio.in:444 in
# dev/staging/test, https://api.digio.in in production), while the panel script is served from
# https://ext.digio.in (sandbox) or https://app.digio.in (production). DIGIO_SDK_BASE_URL overrides the
# derived value when needed.
#
# Worked example E19 — openspec/changes/embedded-esign-digio/design.md#worked-examples
module DigioSdkConfig
  SANDBOX_BASE_URL = "https://ext.digio.in".freeze
  PRODUCTION_BASE_URL = "https://app.digio.in".freeze
  SDK_PATH = "/sdk/v11/digio.js".freeze

  module_function

  # @return [String] scheme and host the SDK is served from, no trailing slash
  def base_url
    override = ENV["DIGIO_SDK_BASE_URL"].to_s.strip.chomp("/")
    return override if override.present?

    ENV["DIGIO_BASE_URL"].to_s.include?("ext.digio.in") ? SANDBOX_BASE_URL : PRODUCTION_BASE_URL
  end

  # @return [String] the script the signing page loads
  def script_url
    "#{base_url}#{SDK_PATH}"
  end

  # @return [String] "sandbox" or "production", as the SDK's `environment` option expects
  def environment
    base_url.include?("ext.digio.in") ? "sandbox" : "production"
  end
end
