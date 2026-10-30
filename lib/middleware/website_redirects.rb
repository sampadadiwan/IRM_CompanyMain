require "yaml"

# Permanent redirects for retired company-website URLs, read from ONE source
# file (website_src/redirects.yml) by both places that serve the site:
#
#   * config/deploy/templates/nginx_conf.erb — production, where nginx serves
#     the apex straight off disk and puma never sees the request;
#   * lib/middleware/website.rb (this directory) — dev/test and the
#     production fallback.
#
# Keeping the list in one file is what stops the two from drifting: a URL
# redirected in dev but 404ing in production is exactly the bug this exists
# to prevent. Plain Ruby with no Rails dependency, because the nginx template
# is rendered by Capistrano on the deploying machine, outside any Rails app.
module WebsiteRedirects
  SOURCE = File.expand_path("../../website_src/redirects.yml", __dir__).freeze

  # { "/about-us" => "/about.html", ... } with every source path normalised
  # (see .normalize), so a lookup only has to normalise the request path the
  # same way. An absent file means "no redirects", not an error — a stage
  # that has never had a legacy site has nothing to list.
  def self.load(path = SOURCE)
    return {} unless File.exist?(path)

    # safe_load: the file is data, never objects; nil for an all-comment file.
    raw = YAML.safe_load_file(path) || {}
    raise ArgumentError, "#{path}: expected a mapping of old path => new path" unless raw.is_a?(Hash)

    raw.each_with_object({}) do |(from, to), map|
      # Both sides must be site-relative paths: an absolute URL on the right
      # would turn the site into an open redirector, and a bare word on the
      # left could never match a request path.
      relative = from.to_s.start_with?("/") && to.to_s.start_with?("/")
      raise ArgumentError, "#{path}: #{from.inspect} => #{to.inspect} must both start with /" unless relative

      # Redirecting "/" would take the homepage itself away.
      raise ArgumentError, "#{path}: the site root / cannot be redirected" if normalize(from) == "/"

      map[normalize(from)] = to.to_s
    end.freeze
  end

  # "/about-us/" and "/about-us" are the same old page — WordPress linked the
  # slashed form but people and other sites type both — so drop one trailing
  # slash and downcase. "/" itself is left alone.
  def self.normalize(path)
    path = path.to_s.downcase
    path.length > 1 ? path.delete_suffix("/") : path
  end
end
