# frozen_string_literal: true

# Checks the navigation references inside user-guide text: app paths must be Markdown links
# that route (never raw paths in backticks), and links to other guides must point at a guide
# that exists.
#
# Shared by UserGuideLint (Markdown guide files) and FaqEntry
# (answers written in FAQ Manager, and FaqVerificationJob's nightly re-check), so a path
# that fails one fails all three.
#
# @example
#   GuideReferenceCheck.errors("Open [**Funds**](/funds) then see [Units](fund_units_user_guide).",
#                              guide_key: "capital_calls_user_guide")
#   #=> []
module GuideReferenceCheck
  GUIDES_DIR = "docs/user_guides"

  # A backticked absolute app path, with an optional query string: `/funds?tab=x`.
  PATH_IN_BACKTICKS = %r{`(/[a-zA-Z0-9_:<>{}\[\]/.=&?%-]*)`}

  # A Markdown link target that is not an in-page anchor.
  LINK = /\]\(([^)\s#]+?)(?:#[^)]*)?\)/

  module_function

  # @param text [String] Markdown
  # @param guide_key [String] guide the text belongs to, e.g. "agents/call_notice_agent_user_guide";
  #   relative links resolve against its directory
  # @return [Array<String>] one message per broken reference, empty when all resolve
  def errors(text, guide_key:)
    path_errors(text) + link_errors(text, guide_key: guide_key)
  end

  # Readers do not type URLs, so guide text must not show app paths in backticks: a fixed path
  # becomes a Markdown link on the words to click, and a path with a placeholder is described
  # in words instead.
  #
  # @param text [String]
  # @return [Array<String>] one message per backticked app path
  def path_errors(text)
    text.to_s.scan(PATH_IN_BACKTICKS).flatten.map do |path|
      "shows the raw path #{path} — link the on-screen label instead, e.g. [**Funds**](/funds), or describe it in words"
    end
  end

  # @param text [String]
  # @param guide_key [String]
  # @return [Array<String>] "missing guide x" / "unroutable link /x" messages
  def link_errors(text, guide_key:)
    from_dir = Pathname.new(GUIDES_DIR).join(guide_key).dirname
    text.to_s.scan(LINK).flatten.filter_map do |target|
      next if target.match?(/\A[a-z][a-z0-9+.-]*:/i) # http:, mailto:, etc.

      if target.start_with?("/user_guides/")
        resolved = Pathname.new(GUIDES_DIR).join(target.delete_prefix("/user_guides/").delete_suffix(".md"))
      elsif target.start_with?("/")
        next "unroutable link #{target}" unless routable?(target)

        next
      else
        resolved = (from_dir + target.delete_suffix(".md")).cleanpath
      end
      "missing guide #{target}" unless Rails.root.join("#{resolved}.md").exist?
    end
  end

  # @param path [String] a path from guide text, possibly with placeholders and a query string
  # @return [Boolean] whether Rails routes it (any verb), a mounted engine owns it, or public/ serves it
  def routable?(path)
    bare = path.split("?").first.to_s
    bare = bare.gsub(/:[a-z_]+|<[^>]+>|\{[^}]+\}|\[[^\]]+\]/, "1").squeeze("/")
    return true if bare.empty? || bare == "/"
    return true if mount_prefixes.any? { |prefix| bare == prefix || bare.start_with?("#{prefix}/") }
    return true if Rails.public_path.join(bare.delete_prefix("/")).file?

    %i[get post patch put delete].any? do |verb|
      Rails.application.routes.recognize_path(bare, method: verb)
      true
    rescue ActionController::RoutingError, NoMethodError
      false
    end
  end

  # Engines mounted into the app (Blazer, Sidekiq::Web, …) are not visible to recognize_path.
  #
  # @return [Array<String>]
  def mount_prefixes
    @mount_prefixes ||= Rails.application.routes.routes.filter_map do |route|
      app = route.app
      app = app.rack_app if app.respond_to?(:rack_app)
      engine = app.respond_to?(:routes) || (app.respond_to?(:call) && !app.is_a?(ActionDispatch::Routing::RouteSet::Dispatcher))
      route.path.spec.to_s.delete_suffix("(.:format)") if engine
    end.reject { |p| p.include?(":") || p.include?("*") }.uniq
  end
end
