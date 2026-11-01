# frozen_string_literal: true

# Which OAuth clients are which: the MCP client kinds of config/mcp_clients.yml.
#
# Three callers:
# * POST /oauth/registration (config/initializers/doorkeeper_openid_connect.rb) — a client may
#   register only with redirect URIs of one known kind, and never under a reserved name.
# * McpController#enforce_entity_governance! — an entity's "Allowed AI Clients" holds kinds, and a
#   token's app is classified by its redirect URI, not by the name it registered with.
# * The entity form and page — list and label the kinds.
#
# docs/security/security_review_2026_10.md "Authentication and session — Medium / Low", M2 and N5.
class McpClientRegistry
  # Allowlists saved before kinds existed hold app names ("Claude"). Names a kind lists under
  # legacy_names count as that kind; any other saved name is still matched against the app's name
  # (M2-4) until this date, after which only kinds count. Re-saving the entity form converts.
  LEGACY_NAMES_UNTIL = Date.new(2027, 1, 31)

  Refusal = Struct.new(:error, :description, keyword_init: true)

  class << self
    # @return [Hash{String => Hash}] kind => { label:, legacy_names:, patterns: [Regexp] }
    def kinds
      @kinds ||= (config[:kinds] || {}).to_h do |kind, spec|
        [kind.to_s, { label: spec[:label].to_s,
                      legacy_names: Array(spec[:legacy_names]).map(&:to_s),
                      patterns: Array(spec[:redirect_patterns]).map { |pattern| Regexp.new(pattern) } }]
      end
    end

    # @return [Array<String>] names no self-registered client may use (compared case-insensitively)
    def reserved_names
      @reserved_names ||= ([MailAddinToken::APPLICATION_NAME] + Array(config[:reserved_names])).map { |name| normalize(name) }.uniq
    end

    # Why a dynamic registration must be refused, or nil to let it through.
    # @param name [String, nil] the client_name the client asked for
    # @param redirect_uris [Array<String>, String, nil]
    # @return [Refusal, nil]
    def registration_refusal(name:, redirect_uris:)
      uris = Array(redirect_uris).map(&:to_s)
      # M2-2 / N5 — a first-party or reserved name ("CapHive Mail Add-in" with the out-of-band URI)
      return Refusal.new(error: "invalid_client_metadata", description: "This client name is reserved.") if reserved_name?(name)
      # M2-1 / M2-3 — every redirect must belong to one known kind: no other hosts, no urn:, no http
      return nil if uris.any? && kind_for_uris(uris)

      Refusal.new(error: "invalid_redirect_uri",
                  description: "Redirect URIs must be those of a supported AI client (#{kinds.values.pluck(:label).join(', ')}).")
    end

    # @param application [Doorkeeper::Application, nil]
    # @return [String, nil] the kind its redirect URIs belong to
    def kind_for(application)
      return nil if application.nil?

      kind_for_uris(application.redirect_uri.to_s.split)
    end

    # M2-4 — whether a token's app passes an entity's "Allowed AI Clients" list.
    # @param application [Doorkeeper::Application, nil]
    # @param allowed [Array<String>] the entity's saved list (kinds, or legacy app names)
    def allowed?(application, allowed)
      kind = kind_for(application)
      # Kinds, plus the kinds legacy names map to ("Claude" => claude)
      return true if kind && allowed_kinds(allowed).include?(kind)
      # Saved names that map to no kind are matched by name for one release only
      return false if Date.current > LEGACY_NAMES_UNTIL || application.nil?

      return false unless unmapped_entries(allowed).include?(application.name)

      Rails.logger.warn("[McpClientRegistry] client #{application.uid} allowed by legacy name #{application.name.inspect}; " \
                        "allow its kind instead before #{LEGACY_NAMES_UNTIL}")
      true
    end

    # @return [String] what to call a client in messages and on the entity page
    def label_for(application)
      kind = kind_for(application)
      kind ? kinds[kind][:label] : application&.name.to_s
    end

    # @return [String] the label of a saved allowlist entry (a kind, or a legacy name as saved)
    def label_for_entry(entry)
      kinds.dig(entry, :label) || entry
    end

    # Saved entries that are neither a kind nor a legacy name of one: shown on the entity form so
    # saving it does not silently drop them (an emptied list would allow every client)
    def unmapped_entries(allowed)
      allowed - kinds.keys - kinds.values.flat_map { |spec| spec[:legacy_names] }
    end

    # @return [Array<String>] the kinds a saved list allows, legacy names translated
    def allowed_kinds(allowed)
      kinds.filter_map { |kind, spec| kind if allowed.include?(kind) || spec[:legacy_names].intersect?(allowed) }
    end

    # Config is read once per process; tests that stub it clear the memo
    def reset!
      @config = @kinds = @reserved_names = nil
    end

    private

    def config
      @config ||= Rails.application.config_for(:mcp_clients)
    end

    # The one kind whose patterns match every URI, or nil
    def kind_for_uris(uris)
      return nil if uris.empty?

      kinds.find { |_kind, spec| uris.all? { |uri| spec[:patterns].any? { |pattern| pattern.match?(uri) } } }&.first
    end

    def reserved_name?(name)
      normalized = normalize(name)
      reserved_names.include?(normalized) || normalized.start_with?("caphive")
    end

    def normalize(name)
      name.to_s.unicode_normalize(:nfkc).strip.squeeze(" ").downcase
    end
  end
end
