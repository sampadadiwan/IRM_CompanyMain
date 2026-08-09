require "erb"
require "yaml"
require "digest"

# Build the static company website from website_src/ into public/website/.
#
# website_src/ is the SOURCE. public/website/ is GENERATED OUTPUT and is still
# committed, so a deploy never has to run the build — but never hand-edit a page
# there, it will be overwritten on the next build.
#
#   website_src/_layout.html.erb   the one skeleton every page renders through
#   website_src/_partials/         nav, mobile menu, footer, script tags
#   website_src/pages/<name>.html  YAML front matter + that page's body only
#
# Assets (assets/css, assets/js, assets/img) are NOT templated and stay in
# public/website — the build only writes *.html. It stamps their URLs with a
# content hash, which is why the old restamp-assets.sh is no longer needed.
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

      pages.each do |path|
        name = File.basename(path)
        fm, content = parse(File.read(path), path)
        ctx = Context.new(name: name, front_matter: fm, content: content, builder: self)
        File.write(File.join(@out, name), layout.result(ctx.binding_for))
      end
      puts "website: built #{pages.size} pages -> #{@out.sub(ROOT + '/', '')}"
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
