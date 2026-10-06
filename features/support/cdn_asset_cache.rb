# frozen_string_literal: true

# Serves the third-party CDN assets our pages load (jQuery, SheetJS, DataTables, ag-Grid, ...) to
# the Playwright browser from a disk cache, so a scenario's page load never waits on a slow CDN.
#
# WHY: the logged-in layouts load ~12 render-blocking scripts and styles from 6+ CDN hosts, and
# `visit` waits for the browser `load` event. In a 6-worker run every one of the 12 Playwright
# "Timeout 30000ms exceeded" failures had a CDN request still pending at ~30 s (cdn.sheetjs.com in 7
# of them; it is also not browser-cached, so every page load fetched it again). Reruns passed.
#
# HOW: each new browser context gets one route for the CDN hosts below. The first time a URL is seen
# it is fetched once and written to tmp/playwright_cdn_cache; every later request, from any parallel
# worker, is answered from disk. Anything we cannot cache safely goes to the network exactly as before.
#
# Only text assets (JS/CSS) are cached: Playwright's `fulfill(body:)` sends a String as text, which
# would corrupt binary files such as fonts and images, so those are fetched as usual. Unpinned URLs
# (`@latest`) and redirected URLs are never cached. A cached file older than 7 days is refetched.
#
#   CDN_CACHE=0                          bypass the cache entirely (behave as before)
#   rm -rf tmp/playwright_cdn_cache      throw the cache away
require "digest"
require "fileutils"
require "json"
require "capybara/playwright"

module CdnAssetCache
  # Static-asset hosts the layouts and the importmap load from (seen in a full parallel run). Anything
  # else - analytics, maps, APIs - is never intercepted.
  HOSTS = %w[
    cdn.jsdelivr.net cdnjs.cloudflare.com unpkg.com code.jquery.com cdn.sheetjs.com
    cdn.datatables.net vjs.zencdn.net fonts.googleapis.com releases.transloadit.com
  ].freeze
  # `^`, not `\A`: Playwright hands this Regexp to the browser's JavaScript engine, where `\A` is just "A".
  URL_PATTERN = %r{^https?://(?:#{HOSTS.map { |h| Regexp.escape(h) }.join('|')})/}
  DIR = Rails.root.join("tmp/playwright_cdn_cache")
  MAX_AGE_SECONDS = 7 * 24 * 3600
  MAX_BYTES = 10 * 1024 * 1024
  # Below Playwright's 30 s navigation timeout, so a dead CDN falls through to the network path
  # (which fails the way it does today) instead of us holding the request past the timeout.
  FETCH_TIMEOUT_MS = 25_000
  # JS / CSS / JSON only. UTF-8 (or no charset) so a String body is sent unchanged.
  TEXT_TYPE = %r{\A(?:text/(?:css|javascript|ecmascript)|application/(?:javascript|x-javascript|ecmascript|json))(?:\s*;\s*charset=utf-?8)?\s*\z}i
  # Describe the transfer rather than the content; Playwright / the browser recompute them.
  SKIP_HEADERS = %w[content-encoding content-length transfer-encoding connection keep-alive set-cookie].freeze

  @stats = Hash.new(0)
  @uncached = {}
  @mutex = Mutex.new

  class << self
    attr_reader :stats, :uncached

    def enabled? = ENV["CDN_CACHE"] != "0"

    # Called once for every new browser context (one per scenario that opens a browser).
    def install(context)
      return unless enabled?

      context.route(URL_PATTERN, ->(route, request) { handle(route, request) })
    end

    def handle(route, request)
      url = request.url
      return route.continue unless request.method == "GET" && cacheable_url?(url)

      entry = read(url)
      if entry
        count(:hits)
        return route.fulfill(status: 200, headers: replay_headers(entry[:headers], entry[:body]), body: entry[:body])
      end

      fetch_and_store(route, request, url)
    rescue StandardError => e
      # Never fail a scenario because of the cache: let the browser go to the network itself.
      count(:errors)
      note_error(e)
      begin
        route.continue
      rescue StandardError
        nil # already handled
      end
    end

    private

    # `@latest` / `/latest/` change under us, so they are never cached.
    def cacheable_url?(url) = !url.match?(%r{@latest\b|/latest/})

    def fetch_and_store(route, request, url)
      response = route.fetch(timeout: FETCH_TIMEOUT_MS)
      body = response.body

      if storable?(response, request, body)
        write(url, response.headers, body)
        count(:misses)
        # The body is valid UTF-8 text (checked in storable?), so Playwright sends it as text.
        route.fulfill(status: 200, headers: replay_headers(response.headers, body), body: body.dup.force_encoding(Encoding::UTF_8))
      else
        # Binary, non-200, redirected or too big: hand back the fetched response untouched. Playwright
        # replays it server-side, so binary bytes are not mangled.
        count(:uncached)
        note_uncached(url, response)
        route.fulfill(response: response)
      end
    end

    def storable?(response, request, body)
      return false unless response.status == 200 && response.url == request.url
      return false unless response.headers["content-type"].to_s.match?(TEXT_TYPE)
      return false if body.bytesize > MAX_BYTES

      body.dup.force_encoding(Encoding::UTF_8).valid_encoding?
    end

    # The stored headers, minus transfer headers, with the BYTE length. Playwright would otherwise
    # compute content-length from the character count, which is short for multi-byte text.
    def replay_headers(headers, body)
      headers.reject { |name, _| SKIP_HEADERS.include?(name.to_s.downcase) }.merge("content-length" => body.bytesize.to_s)
    end

    def paths(url)
      key = Digest::SHA256.hexdigest(url)
      [DIR.join("#{key}.json"), DIR.join("#{key}.body")]
    end

    # nil when the URL is not cached or the entry is stale. The .json file is written last, so its
    # presence means the .body beside it is complete.
    def read(url)
      meta_path, body_path = paths(url)
      return nil unless File.exist?(meta_path) && File.exist?(body_path)
      return nil if File.mtime(meta_path) < Time.current - MAX_AGE_SECONDS

      { headers: JSON.parse(File.read(meta_path)).fetch("headers"), body: File.read(body_path, encoding: Encoding::UTF_8) }
    end

    # Write-then-rename, so another parallel worker never reads a half-written file.
    def write(url, headers, body)
      FileUtils.mkdir_p(DIR)
      meta_path, body_path = paths(url)
      { body_path => body, meta_path => JSON.generate(url:, headers:) }.each do |path, content|
        tmp = "#{path}.#{Process.pid}.tmp"
        File.binwrite(tmp, content)
        File.rename(tmp, path)
      end
    end

    def count(key) = @mutex.synchronize { @stats[key] += 1 }

    # Which URLs were left to the network and why, for the summary line at the end of the run.
    def note_uncached(url, response)
      @mutex.synchronize { @uncached[url] ||= "#{response.status} #{response.headers['content-type']}" }
    end

    # Print the first few errors only; the counter shows how many there were. $stderr.puts, not `warn`:
    # pcuc runs with RUBYOPT=-W0, which turns Kernel#warn into a no-op.
    def note_error(error)
      return if @stats[:errors] > 3

      $stderr.puts "CDN asset cache: #{error.class}: #{error.message.to_s.lines.first&.strip}" # rubocop:disable Style/StderrPuts
    end
  end
end

# A new Capybara::Playwright::Browser (and so a new browser context) is built lazily for each
# scenario that opens a page, so hooking context creation installs the route only where a browser is
# actually used - no browser is launched for scenarios that never visit a page.
module CdnAssetCache
  module BrowserContextHook
    private

    def create_browser_context
      super.tap { |context| CdnAssetCache.install(context) }
    end
  end
end
Capybara::Playwright::Browser.prepend(CdnAssetCache::BrowserContextHook)

# One line per worker, so a run shows whether the cache was used.
at_exit do
  stats = CdnAssetCache.stats
  if stats.any?
    puts "CDN asset cache [worker #{ENV.fetch('TEST_ENV_NUMBER', '-')}]: #{stats.map { |k, v| "#{k}=#{v}" }.join(' ')}"
    CdnAssetCache.uncached.first(15).each { |url, why| puts "  not cached (#{why}): #{url[0, 130]}" }
  end
end
