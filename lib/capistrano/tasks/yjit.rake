# frozen_string_literal: true

require 'shellwords'

# YJIT + jemalloc rollout for an environment.
#
# Staging and production (IN and US) — see YJIT_STAGES below.
#
#   bundle exec cap production_in yjit:check     # read-only report, changes nothing
#   bundle exec cap production_in yjit:enable    # build, preflight, switch, restart, verify
#   bundle exec cap production_in yjit:disable   # roll back to the plain Ruby
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

# Stages that run on YJIT + jemalloc. One list for all three switches: yjit:enable refuses any
# other stage, and the puma/sidekiq unit templates add the jemalloc LD_PRELOAD only when
# yjit_stage? is true. config.yjit (config/application.rb) must agree — it is on for every
# Rails env, so widen or narrow this list and that line together.
# production_in and production_us both use stage :production, so this covers both regions.
YJIT_STAGES = %w[staging production].freeze

# True for a stage in YJIT_STAGES; also called from the systemd unit ERB templates.
def yjit_stage?
  YJIT_STAGES.include?(fetch(:stage).to_s)
end

def yjit_guard_stage!
  return if yjit_stage?

  raise "yjit:enable is limited to #{YJIT_STAGES.join(', ')}; " \
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

def yjit_has_yjit?(ruby)
  test(*yjit_sh("rvm #{ruby} do ruby -e 'exit(defined?(RubyVM::YJIT.enable) ? 0 : 1)'"))
end

def yjit_plain_name(ruby) = ruby.delete_suffix('-yjit')

def yjit_unit_pid(unit)
  # --no-pager: deploy.rb sets pty, so without it systemctl wraps the PID in pager escape codes
  # and to_i reads 0 (same as the systemctl show calls in config/deploy.rb)
  pid = capture(:systemctl, :show, unit, '-p', 'MainPID', '--value', '--no-pager').strip
  pid.to_i.positive? ? pid : nil
end

def yjit_jemalloc_loaded?(pid)
  pid && test("sudo grep -qs libjemalloc /proc/#{pid}/maps")
end

# YJIT reserves its code region the moment it is enabled, and Ruby names that mapping
# [anon:Ruby:rb_jit_reserve_addr_space] — absent on plain Ruby or with YJIT off. (Named anonymous
# mappings need CONFIG_ANON_VMA_NAME, which the Ubuntu 24.04 app boxes have.) Puma's
# "* Ruby version: ... +YJIT" banner cannot tell: it is printed before Rails loads and runs
# the :enable_yjit initializer, so it never shows +YJIT for a config.yjit-enabled app.
def yjit_running?(pid)
  pid && test("sudo grep -qs jit_reserve_addr_space /proc/#{pid}/maps")
end

def yjit_report
  ruby = yjit_default_ruby
  info "#{host}: RVM default #{ruby} | YJIT compiled in: #{yjit_has_yjit?(ruby) ? 'yes' : 'NO'} | " \
       "libjemalloc2: #{test('dpkg -s libjemalloc2 >/dev/null 2>&1') ? 'installed' : 'missing'}"

  # Per live process: which Ruby binary it runs, and whether YJIT and jemalloc are actually in it
  { puma: fetch(:puma_service_unit_name), sidekiq: fetch(:sidekiq_service_unit_name) }.to_h do |name, unit|
    pid = yjit_unit_pid(unit)
    exe = pid ? capture("sudo readlink /proc/#{pid}/exe").strip : '-'
    running = yjit_running?(pid)
    info "#{host}: #{name} pid #{pid || '-'} #{exe} | YJIT: #{running ? 'running' : 'NOT running'} | " \
         "jemalloc: #{yjit_jemalloc_loaded?(pid) ? 'loaded' : 'not loaded'}"
    [name, running]
  end
end

namespace :yjit do
  desc 'Report YJIT and jemalloc status on each host (read-only)'
  task :check do
    # do...end, not braces: `on roles(:app) { ... }` binds the block to roles(), leaving `on` blockless
    on roles(:app) do
      yjit_report
    end
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

      # Rails enables YJIT while booting, so give a just-restarted process up to a minute to get there
      units = [fetch(:puma_service_unit_name), fetch(:sidekiq_service_unit_name)]
      12.times { units.all? { |unit| yjit_running?(yjit_unit_pid(unit)) } ? break : sleep(5) }
      off = yjit_report.reject { |_name, running| running }.keys
      raise "#{host}: YJIT is not running in #{off.join(' and ')} after restart (see the lines above)" if off.any?

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
