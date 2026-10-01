# frozen_string_literal: true

# The single source of truth for "which regional deployments exist, and where do they live".
#
# Before this class there were three readers of the same two settings, and they disagreed:
# UsersController#cross_site_link ran `eval(ENV["SITES"])` and compared the raw `params[:site]`
# symbol, while EntitySetting, SmsDeliverable and User all read CURRENT_SITE through
# `.strip.upcase`. A user whose `regions` column said "IN, us" therefore minted a credential for
# `:us` that the US deployment (CURRENT_SITE=US) rejected forever — silently, because every
# rejection rendered the same "Invalid or expired link" string.
#
# So: one accessor, one canonical form (stripped + upcased), parsed once per process.
#
# SITES is JSON, not a Ruby literal. The old form was fed to `eval` at request time behind a
# `rubocop:disable Security/Eval`, which made a mistyped environment variable a code-execution
# sink. Every URL must be https: the old values were http, which cost each region switch an
# extra India-to-US round trip through the load balancer's scheme-upgrade redirect — real
# latency spent against what used to be a 30-second credential.
class SiteRegistry
  class ConfigurationError < StandardError; end

  # Published so callers (and the boot initializer's error message) can name the settings.
  SITES_VAR   = "SITES"
  CURRENT_VAR = "CURRENT_SITE"

  # Loopback hosts are exempt from the https rule - development and the Cucumber suite
  # serve plain http on localhost with no TLS terminator in front of them.
  LOCAL_HOSTS = %w[localhost 127.0.0.1 0.0.0.0 ::1].freeze

  class << self
    # Every deployed region code, canonical form, sorted. e.g. ["IN", "US"]
    def codes
      sites.keys.sort.freeze
    end

    # This deployment's own region code, e.g. "US" on the US boxes.
    def current_code
      @current_code ||= begin
        code = normalize(ENV.fetch(CURRENT_VAR, nil))
        raise ConfigurationError, "#{CURRENT_VAR} is not set" if code.nil?
        unless sites.key?(code)
          raise ConfigurationError,
                "#{CURRENT_VAR} is #{code.inspect} but #{SITES_VAR} only defines #{codes.join(', ')}"
        end

        code
      end
    end

    # The other regions a user can be handed off to from here.
    def peers
      codes - [current_code]
    end

    # Base URL for a region, without a trailing slash, or nil when the region is not deployed.
    # Callers build redirect targets from THIS and never from request input - that is what keeps
    # `redirect_to ..., allow_other_host: true` constrained to an allow-list.
    def url_for(code)
      sites[normalize(code)]
    end

    def known?(code)
      sites.key?(normalize(code))
    end

    # The canonical form of a region code. Matches CanonicalFingerprint#normalize_region, which
    # is what the multi-region user sync already writes into users.regions.
    def normalize(code)
      value = code.to_s.strip
      return nil if value.empty?

      value.upcase
    end

    # Called from config/initializers/site_registry.rb so a bad setting fails the boot rather
    # than one user's region switch, hours later, with no log line.
    def validate!
      sites
      current_code
      true
    end

    # Test support only - the parsed settings are memoised per process, so a scenario that
    # stubs ENV must clear them or it leaks into the next scenario.
    def reset!
      raise ConfigurationError, "reset! is not available in production" if Rails.env.production?

      @sites = nil
      @current_code = nil
    end

    private

    # Parsed once. Raises rather than returning a partial map: a half-usable region list is how
    # a switch ends up redirecting to nil.
    def sites
      @sites ||= begin
        raw = ENV.fetch(SITES_VAR, nil)
        raise ConfigurationError, "#{SITES_VAR} is not set" if raw.to_s.strip.empty?

        parsed = parse(raw)
        parsed.each_with_object({}) do |(code, url), map|
          key = normalize(code)
          raise ConfigurationError, "#{SITES_VAR} has a blank region code" if key.nil?

          map[key] = validated_url(key, url)
        end.freeze
      end
    end

    def parse(raw)
      parsed = JSON.parse(raw)
      raise ConfigurationError, "#{SITES_VAR} must be a JSON object, got #{parsed.class}" unless parsed.is_a?(Hash)

      parsed
    rescue JSON::ParserError => e
      raise ConfigurationError, "#{SITES_VAR} is not valid JSON: #{e.message}"
    end

    # https is a hard requirement for any real host, not a preference: the hand-off credential
    # rides in the query string, so an http base URL puts it on the wire in clear text AND costs
    # the switch an extra round trip through the load balancer's scheme-upgrade redirect.
    #
    # The exemption is by HOST, not by Rails.env, so a staging box pointing at an
    # http://app.example.com still fails the boot.
    def validated_url(code, url)
      uri = URI.parse(url.to_s)
      raise ConfigurationError, "#{SITES_VAR}[#{code}] has no host" if uri.host.to_s.empty?

      unless uri.scheme == "https" || LOCAL_HOSTS.include?(uri.host)
        raise ConfigurationError,
              "#{SITES_VAR}[#{code}] must be an https URL, got #{url.inspect}"
      end

      url.to_s.sub(%r{/+\z}, "")
    rescue URI::InvalidURIError
      raise ConfigurationError, "#{SITES_VAR}[#{code}] is not a valid URL: #{url.inspect}"
    end
  end
end
