# lib/capistrano/tasks/website.rake
#
# Intraday deploy of the static company website ONLY.
#
# nginx serves the site straight off disk from
# /home/ubuntu/IRM/current/public/website (see config/deploy/templates/
# nginx_conf.erb and docs/modules/website/website_serving.md) — puma never sees that
# traffic. So a copy change, a new page or a CSS tweak needs nothing more than
# those files landing on the box: no bundle, no assets:precompile, no migrate,
# no puma/sidekiq restart, no new release directory.
#
#   bundle exec cap production_in website:deploy      # build + upload + verify
#   bundle exec cap production_us website:deploy
#   bundle exec cap production_in website:upload      # upload what's on disk
#   bundle exec cap production_in website:verify      # just check what's live
#
# IMPORTANT — this patches the CURRENT RELEASE in place. public/website is
# git-tracked, so the next full `cap deploy` re-checks it out from the deploy
# branch: commit and push the same change or it silently reverts on the next
# full deploy. website:deploy warns loudly when the working tree is dirty.

namespace :website do
  # Every stage lists :web on all app servers; that is the set of boxes with an
  # nginx that could be asked for the site. The upload target is deliberately
  # current_path (not release_path): release_path has no meaning outside a
  # running deploy, and `current` is literally the path baked into nginx's root.

  desc "Render website_src/ into public/website/ locally (wraps rake website:build)"
  task :build do
    run_locally do
      # Same builder the full deploy relies on having been run before commit.
      # Passed as ONE string on purpose: SSHKit only applies its command map to
      # a bare command word, and capistrano/rvm maps :bundle to an rvm wrapper
      # meant for the SERVERS — which does not resolve in the local shell.
      execute "bundle exec rake website:build"
    end
  end

  desc "Upload public/website/ to the live release and reload nothing else"
  task :upload do
    # One tarball built once, reused for every server in the stage. 80-odd
    # files over SFTP one-by-one is minutes; one 2.5 MB tarball is seconds.
    archive       = "tmp/website-deploy.tar.gz"
    remote_tar    = "/tmp/website-deploy-#{Time.now.utc.strftime('%Y%m%d%H%M%S')}.tar.gz"
    local_files   = nil
    local_index   = nil

    run_locally do
      unless File.directory?("public/website")
        raise "public/website does not exist — run `bundle exec cap #{fetch(:stage)} website:build` first"
      end

      execute :mkdir, "-p", "tmp"
      # -C public so the archive contains a single top-level `website/` dir,
      # which makes the remote extract self-describing and hard to get wrong.
      execute :tar, "-czf", archive, "-C", "public", "website"

      # Captured now so the remote side can be checked against them below —
      # a truncated upload or a half-extracted tar shows up as a count mismatch.
      local_files = capture(:find, "public/website", "-type", "f").lines.size
      local_index = capture(:sha256sum, "public/website/index.html").split.first
      info "website: #{local_files} files, index.html sha256 #{local_index[0, 12]}"
    end

    on roles(:web), in: :sequence, wait: 2 do |host|
      target   = "#{current_path}/public/website"
      incoming = "/tmp/website-incoming-#{fetch(:stage)}"

      unless test("[ -d #{target} ]")
        raise "#{host}: #{target} missing — has a full deploy ever run on this box?"
      end

      upload! archive, remote_tar

      # Unpack to a scratch dir first so a bad/partial tarball can never leave
      # the live directory in a mixed state.
      execute :rm, "-rf", incoming
      execute :mkdir, "-p", incoming
      execute :tar, "-xzf", remote_tar, "-C", incoming

      # www-data has to be able to read every file nginx will serve; the local
      # umask is not guaranteed to have produced world-readable modes.
      execute :chmod, "-R", "a+rX", "#{incoming}/website"

      if test("command -v rsync >/dev/null 2>&1")
        # Preferred path: rsync mutates files in place with no moment where the
        # vhost root is absent, and --delete prunes pages removed from the build.
        execute :rsync, "-a", "--delete", "#{incoming}/website/", "#{target}/"
      else
        # Fallback: two renames on the same filesystem. Same --delete semantics
        # (the whole directory is replaced), at the cost of a sub-millisecond
        # window where the vhost root does not exist.
        execute :rm, "-rf", "#{target}.old"
        execute :mv, target, "#{target}.old"
        execute :mv, "#{incoming}/website", target
        execute :rm, "-rf", "#{target}.old"
      end

      execute :rm, "-rf", incoming, remote_tar

      # Prove the bytes that landed are the bytes that were built.
      remote_files = capture(:find, target, "-type", "f").lines.size
      remote_index = capture(:sha256sum, "#{target}/index.html").split.first

      if remote_files != local_files || remote_index != local_index
        raise "#{host}: website upload mismatch — " \
              "files #{remote_files}/#{local_files}, index sha #{remote_index[0, 12]}/#{local_index[0, 12]}"
      end

      info "#{host}: website updated — #{remote_files} files, index sha #{remote_index[0, 12]} ✅"
    end

    run_locally { execute :rm, "-f", archive }
  end

  desc "Curl the website vhost on each server and report the status code"
  task :verify do
    domain = fetch(:website_domain, nil)

    # Stages without :website_domain render no website vhost at all
    # (nginx_conf.erb guards on it), so there is nothing to curl.
    if domain.nil?
      warn "website: no :website_domain set for #{fetch(:stage)} — skipping vhost check"
      next
    end

    on roles(:web) do |host|
      # Host header against 127.0.0.1 hits this box's own nginx specifically,
      # bypassing DNS/ALB so a single bad server cannot hide behind the others.
      %w[/ /pricing.html].each do |path|
        code = capture(:curl, "-sS", "-o", "/dev/null", "-w", "'%{http_code}'",
                       "-H", "'Host: #{domain}'", "http://127.0.0.1#{path}").strip
        info "#{host}: #{domain}#{path} → #{code}"
        raise "#{host}: #{domain}#{path} returned #{code}" unless code == "200"
      end
    end
  end

  desc "Build, upload and verify the static website (no app deploy)"
  task :deploy do
    run_locally do
      # public/website is the GENERATED output that a full deploy checks out of
      # git. Anything uploaded here that is not committed disappears the next
      # time someone runs `cap deploy`, which is a confusing way to lose a fix.
      dirty = capture(:git, "status", "--porcelain", "--", "public/website", "website_src").strip.lines
      unless dirty.empty?
        warn "website: #{dirty.size} uncommitted file(s) — commit + push these or the next full deploy reverts them:"
        # A single CSS edit re-stamps every page, so the full list is routinely
        # 60+ lines of noise. Show a handful and the count.
        dirty.first(8).each { |l| warn "  #{l.rstrip}" }
        warn "  ... and #{dirty.size - 8} more" if dirty.size > 8
      end
    end

    invoke "website:build"
    invoke "website:upload"
    invoke "website:verify"
  end
end
