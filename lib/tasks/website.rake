require "erb"
require "yaml"
require "digest"
require_relative "../middleware/website_redirects"

# Build the static company website from website_src/ into public/website/.
#
# website_src/ is the SOURCE. public/website/ is GENERATED OUTPUT and is still
# committed, so a deploy never has to run the build — but never hand-edit a page
# there, it will be overwritten on the next build.
#
#   website_src/_layout.html.erb   the one skeleton every page renders through
#   website_src/_partials/         nav, mobile menu, footer, script tags
#   website_src/pages/<name>.html  YAML front matter + that page's body only
#   website_src/redirects.yml      old-site URL -> page 301s (checked, not rendered)
#
# The build also writes public/website/sitemap.xml from the page list, and
# aborts if a redirect in redirects.yml points at a page that does not exist.
#
# Assets (assets/css, assets/js, assets/img) are NOT templated and stay in
# public/website — the build only writes *.html and sitemap.xml. It stamps
# asset URLs with a content hash, which is why the old restamp-assets.sh is
# no longer needed.
module WebsiteBuild
  ROOT = File.expand_path("../..", __dir__).freeze
  SRC  = File.join(ROOT, "website_src").freeze
  OUT  = File.join(ROOT, "public", "website").freeze
  BASE = "https://caphive.com/".freeze

  # The binding every template is rendered against. Everything a page or partial
  # may reference is a method here — nothing else is in scope, so a typo in a
  # template fails the build instead of silently rendering an empty string.
  class Context
    attr_reader :title, :description, :og_title, :og_description, :content

    def initialize(name:, front_matter:, content:, builder:)
      @name    = name
      @fm      = front_matter
      @content = content
      @builder = builder

      @title          = @fm.fetch("title")
      @description    = @fm.fetch("description")
      # og_* fall back to the page title/description rather than being repeated
      @og_title       = @fm["og_title"] || @title
      @og_description = @fm["og_description"] || @description
    end

    # Canonical and og:url are always the file's own URL, so pages never carry
    # them — index.html is the site root rather than /index.html.
    def canonical
      BASE + (@name == "index.html" ? "" : @name)
    end

    def body_attrs
      @fm["data_page"] ? %( data-page="#{@fm['data_page']}") : ""
    end

    # Optional; only 404.html sets it today.
    def robots
      @fm["robots"] ? %(<meta name="robots" content="#{@fm['robots']}">\n) : ""
    end

    # The long-form pieces under /resources are og:type article; everything else
    # is a plain page.
    def og_type = @fm["og_type"] || "website"

    # Maintainer notes that sit above the nav on a handful of pages ("DRAFT FOR
    # REVIEW", 404's server-config note). Kept verbatim so nothing is lost.
    def body_top = @fm["body_top"].to_s

    def head_extra
      @fm["head_extra"] ? partial(@fm["head_extra"]) : ""
    end

    # Pages default to the shared bundle; index.html overrides with its own.
    def scripts = partial(@fm["scripts"] || "scripts")

    # Structured data (BlogPosting JSON-LD) on the long-form pieces, emitted
    # after the script tag exactly where it sits today.
    def body_extra = @fm["body_extra"].to_s

    def partial(name) = @builder.partial(name, self)
    def asset(path)   = @builder.asset(path)
    def binding_for   = binding
  end

  class Builder
    def initialize(out: OUT, src: SRC)
      @out = out
      @src = src
      @partials = {}
      @assets   = {}
    end

    def build
      layout = ERB.new(File.read(File.join(@src, "_layout.html.erb")), trim_mode: "-")
      layout.filename = "_layout.html.erb"

      pages = Dir[File.join(@src, "pages", "*.html")].sort
      abort "No pages found in #{@src}/pages" if pages.empty?

      # Pages that belong in the sitemap, collected while rendering so the
      # sitemap is derived from exactly the pages that were just written.
      indexable = []
      pages.each do |path|
        name = File.basename(path)
        fm, content = parse(File.read(path), path)
        ctx = Context.new(name: name, front_matter: fm, content: content, builder: self)
        File.write(File.join(@out, name), layout.result(ctx.binding_for))
        # A page that sets `robots` (404, thank-you: noindex) must not be
        # advertised to crawlers it asks to stay away.
        indexable << [name, path] unless fm["robots"]
      end
      check_redirects!
      write_sitemap(indexable)
      puts "website: built #{pages.size} pages -> #{@out.sub(ROOT + '/', '')}"
      puts "         sitemap.xml: #{indexable.size} URLs; redirects.yml: #{WebsiteRedirects.load.size} old URLs, all targets present"
      puts "         " + @assets.map { |p, v| "#{File.basename(p)}?v=#{v}" }.join("  ") unless @assets.empty?
    end

    # Rendered against the calling page's context, not memoised — the scripts
    # partial carries that page's JSON-LD. Only the parsed template is cached.
    def partial(name, ctx)
      erb   = File.join(@src, "_partials", "#{name}.html.erb")
      plain = File.join(@src, "_partials", name.end_with?(".html") ? name : "#{name}.html")
      if File.exist?(erb)
        template = (@partials[erb] ||= begin
          t = ERB.new(File.read(erb), trim_mode: "-")
          t.filename = erb
          t
        end)
        template.result(ctx.binding_for)
      elsif File.exist?(plain)
        @partials[plain] ||= File.read(plain)
      else
        raise "website: no partial #{name} (looked for #{erb} and #{plain})"
      end
    end

    # /assets/ is served with max-age=86400 by both nginx and the Rails
    # middleware, so every asset URL carries a content hash. Change the file and
    # the URL changes with it; nothing to remember to run.
    def asset(path)
      file = File.join(@out, path)
      raise "website: asset not found: #{file}" unless File.exist?(file)
      "#{path}?v=#{@assets[path] ||= Digest::MD5.file(file).hexdigest[0, 8]}"
    end

    private

    # Every target in website_src/redirects.yml must be a page that exists,
    # or nginx would 301 an old link straight into a 404 — worse than the
    # plain 404 it replaced, because the redirect gets cached. Checked
    # against the output folder, after the pages have been written.
    def check_redirects!
      missing = WebsiteRedirects.load.reject { |_from, to| File.exist?(File.join(@out, to)) }
      return if missing.empty?

      lines = missing.map { |from, to| "  #{from} -> #{to}" }.join("\n")
      abort "website: redirects.yml points at pages that do not exist:\n#{lines}"
    end

    # Generated rather than hand-kept: the hand-written file drifted (two live
    # pages missing, most entries undated). <lastmod> is what tells Google and
    # Bing a page changed and is worth re-crawling; <priority>/<changefreq>
    # are left out because Google ignores both.
    def write_sitemap(indexable)
      urls = indexable.map do |name, path|
        loc = BASE + (name == "index.html" ? "" : name)
        "  <url><loc>#{loc}</loc><lastmod>#{lastmod(path)}</lastmod></url>"
      end
      File.write(File.join(@out, "sitemap.xml"), <<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <!--
          GENERATED by `rake website:build` from website_src/pages — do not edit;
          the next build overwrites it. Every page is listed except those whose
          front matter sets `robots` (noindex). URLs must be absolute (sitemap
          protocol); the host comes from WebsiteBuild::BASE.
        -->
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        #{urls.join("\n")}
        </urlset>
      XML
    end

    # Date of the last commit that touched the page source. A page with
    # uncommitted edits (or never committed) uses the file's mtime instead,
    # so a change is dated when it is made rather than when it is committed.
    def lastmod(path)
      dirty = IO.popen(["git", "-C", ROOT, "status", "--porcelain", "--", path], &:read)
      committed = IO.popen(["git", "-C", ROOT, "log", "-1", "--format=%cs", "--", path], &:read).strip
      return committed if dirty.empty? && !committed.empty?

      File.mtime(path).strftime("%Y-%m-%d")
    rescue Errno::ENOENT
      # No git on this machine: the file date is the best we have.
      File.mtime(path).strftime("%Y-%m-%d")
    end

    # "---\n<yaml>\n---\n<body>". The capture keeps its own trailing newline —
    # taking it would silently chomp the last line of a YAML block scalar, which
    # is how the JSON-LD blocks lost the newline before </body>.
    def parse(raw, path)
      m = raw.match(/\A---\n(.*?\n)---\n/m)
      raise "website: #{path} has no YAML front matter" unless m
      [YAML.safe_load(m[1]), m.post_match]
    end
  end
end

namespace :website do
  desc "Render website_src/ into public/website/ (the deployed static site)"
  task :build do
    WebsiteBuild::Builder.new.build
  end
end
