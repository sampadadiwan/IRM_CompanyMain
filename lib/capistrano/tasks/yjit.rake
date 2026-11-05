# frozen_string_literal: true

require 'shellwords'

# YJIT + jemalloc rollout for an environment.
#
# Staging only for now — see YJIT_STAGES below.
#
#   bundle exec cap staging_in yjit:check     # read-only report, changes nothing
#   bundle exec cap staging_in yjit:enable    # build, preflight, switch, restart, verify
#   bundle exec cap staging_in yjit:disable   # roll back to the plain Ruby
#
# Why a task: config.yjit (config/application.rb) is a silent no-op on a Ruby compiled without
# rustc, which is how rvm built the existing boxes — and jemalloc needs libjemalloc2 on the box
# plus the LD_PRELOAD line in the puma/sidekiq units, but the puma unit is only rewritten by
# IRM:setup. This does all of it, idempotently.
#
# Safety:
# - Builds a SEPARATE `ruby-<version>-yjit` next to the live Ruby. `rvm reinstall` would delete
#   the running Ruby for the ~10 min compile, breaking anything spawned meanwhile (sidekiq
#   restarts, cron `rails runner`).
# - Same version => same gem ABI, so the app's gems in shared/bundle/ruby/<abi> (capistrano-
#   bundler's bundle_path) are reused as-is; only bundler itself is installed into the new Ruby.
# - Boots the deployed release with the new Ruby BEFORE switching anything; a failure stops the
#   task with the live Ruby untouched.
# - Requires the release to contain `config.yjit` — deploy the branch first.
# Hosts are processed one at a time; the restart happens once every host has passed preflight.

YJIT_RVM = 'source ~/.rvm/scripts/rvm &&'

def yjit_sh(cmd)
  [:bash, '-lc', Shellwords.escape("#{YJIT_RVM} #{cmd}")]
end

# Staging-only trial: yjit:enable refuses any other stage, matching config.yjit
# (config/application.rb) and the jemalloc preload in the puma/sidekiq units, which are
# also staging-only until the trial is done. Widen all three together.
YJIT_STAGES = %w[staging].freeze

def yjit_guard_stage!
  return if YJIT_STAGES.include?(fetch(:stage).to_s)

  raise "yjit:enable is limited to #{YJIT_STAGES.join(', ')} during the trial; " \
        "#{fetch(:stage)} is not enabled (see YJIT_STAGES in lib/capistrano/tasks/yjit.rake)"
end

def yjit_dry_run?
  fetch(:sshkit_backend) == SSHKit::Backend::Printer
end

# RVM default Ruby on the host, e.g. "ruby-4.0.6" or "ruby-4.0.6-yjit".
def yjit_default_ruby
  ruby = capture(*yjit_sh('rvm alias show default')).strip.sub(/@.*\z/, '')
  raise "#{host}: no RVM default Ruby set (see IRM:install_ruby)" if ruby.empty? && !yjit_dry_run?

  ruby
end

def yjit_puma_banner
  capture("grep -a 'Ruby version:' #{current_path}/log/puma.error.log 2>/dev/null | tail -1 || true").strip
end

def yjit_has_yjit?(ruby)
  test(*yjit_sh("rvm #{ruby} do ruby -e 'exit(defined?(RubyVM::YJIT.enable) ? 0 : 1)'"))
end

def yjit_plain_name(ruby) = ruby.delete_suffix('-yjit')

def yjit_unit_pid(unit)
  pid = capture(:systemctl, :show, '-p', 'MainPID', '--value', unit).strip
  pid.to_i.positive? ? pid : nil
end

def yjit_jemalloc_loaded?(pid)
  pid && test("sudo grep -qs libjemalloc /proc/#{pid}/maps")
end

def yjit_report
  ruby = yjit_default_ruby
  info "#{host}: RVM default #{ruby} | YJIT compiled in: #{yjit_has_yjit?(ruby) ? 'yes' : 'NO'} | " \
       "libjemalloc2: #{test('dpkg -s libjemalloc2 >/dev/null 2>&1') ? 'installed' : 'missing'}"

  # Puma prints "* Ruby version: ruby 4.0.6 (...) +YJIT +PRISM" at boot; +YJIT appears only
  # when YJIT is actually running, so the last banner is the truth for the live process.
  banner = yjit_puma_banner
  info "#{host}: puma #{banner.empty? ? 'banner not found' : banner.sub(/.*Ruby version: /, '')}"

  { puma: fetch(:puma_service_unit_name), sidekiq: fetch(:sidekiq_service_unit_name) }.each do |name, unit|
    pid = yjit_unit_pid(unit)
    info "#{host}: #{name} pid #{pid || '-'} jemalloc: #{yjit_jemalloc_loaded?(pid) ? 'loaded' : 'not loaded'}"
  end
  banner
end

namespace :yjit do
  desc 'Report YJIT and jemalloc status on each host (read-only)'
  task :check do
    on roles(:app) { yjit_report }
  end

  desc 'Build a YJIT Ruby beside the live one, install jemalloc, switch over, restart and verify'
  task :enable do
    yjit_guard_stage!

    on roles(:app), in: :sequence do
      next info('dry run: skipping') if yjit_dry_run?

      current = yjit_default_ruby
      plain   = yjit_plain_name(current)
      target  = yjit_has_yjit?(current) ? current : "#{plain}-yjit"
      info "#{host}: live Ruby #{current}, target #{target}"

      execute :sudo, 'apt-get -o DPkg::Lock::Timeout=600 install -y rustc libjemalloc2'

      unless yjit_has_yjit?(target)
        info "#{host}: compiling #{target} from source (~10 min); the live Ruby keeps serving"
        execute(*yjit_sh("rvm install #{plain} -n yjit --disable-binary"))
        raise "#{host}: #{target} was built without YJIT — is rustc on PATH?" unless yjit_has_yjit?(target)
      end

      # Bundler is the one gem that lives in the RVM gemset, not shared/bundle.
      bundler = capture(:awk, "'/BUNDLED WITH/{getline; print $1}'", "#{current_path}/Gemfile.lock").strip
      execute(*yjit_sh("rvm #{target} do gem install bundler -v #{bundler} --no-document --conservative")) unless bundler.empty?

      # Preflight: boot the deployed release on the new Ruby. Proves the gems load, and that the
      # release carries config.yjit (prints true only if Rails actually enabled YJIT).
      out = capture(*yjit_sh("cd #{current_path} && RAILS_ENV=#{fetch(:rails_env)} rvm #{target} do " \
                             "bundle exec rails runner 'print RubyVM::YJIT.enabled?'")).strip
      unless out.end_with?('true')
        raise "#{host}: preflight on #{target} printed #{out.lines.last.inspect}, not true — " \
              'is the release deployed with config.yjit? Live Ruby left as is.'
      end
      info "#{host}: preflight passed on #{target}"

      execute(*yjit_sh("rvm --default use #{target}"))

      # Puma's unit is otherwise only rewritten by IRM:setup; refresh it so LD_PRELOAD lands.
      unit = fetch(:puma_service_unit_name)
      rendered = ERB.new(File.read('./config/deploy/services/puma_IRM_env.service.erb')).result(binding)
      upload! StringIO.new(rendered), "/tmp/#{unit}.service"
      execute :sudo, :mv, "/tmp/#{unit}.service", "/etc/systemd/system/#{unit}.service"
      execute :sudo, :systemctl, 'daemon-reload'
    end

    invoke 'sidekiq:install_service'
    invoke 'puma:ensure_clean_restart'
    invoke 'sidekiq:ensure_clean_restart'

    on roles(:app) do
      next if yjit_dry_run?

      # Wait for the restarted puma's boot banner (the log also holds every older one).
      12.times { yjit_puma_banner.include?('+YJIT') ? break : sleep(5) }
      banner = yjit_report
      raise "#{host}: puma banner lacks +YJIT after restart: #{banner}" unless banner.include?('+YJIT')

      info "#{host}: YJIT is live. Watch per-worker RSS for a day; roll back with yjit:disable"
    end
  end

  desc 'Roll back to the plain (non-YJIT) Ruby and restart'
  task :disable do
    on roles(:app) do
      next info('dry run: skipping') if yjit_dry_run?

      plain = yjit_plain_name(yjit_default_ruby)
      execute(*yjit_sh("rvm --default use #{plain}"))
      info "#{host}: RVM default is #{plain} again (the -yjit Ruby is left installed)"
    end
    invoke 'puma:ensure_clean_restart'
    invoke 'sidekiq:ensure_clean_restart'
  end
end
