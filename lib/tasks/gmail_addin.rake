# frozen_string_literal: true

require 'erb'
require 'English' # $CHILD_STATUS, the readable spelling of $? that rubocop's Style/SpecialGlobalVars wants
require 'json'
require 'yaml'

# Build and push the Gmail add-on, one Apps Script project per environment.
GMAIL_ADDON_SRC = 'addons/gmail'
GMAIL_ADDON_CONFIG = 'config/gmail_addins.yml'

# Rails/RakeEnvironment is disabled for the whole namespace on purpose: these tasks touch no
# database and are run from a developer machine against a remote host, so booting Rails
# would only slow them down and require decryptable credentials for an environment the
# developer may not hold keys for.
# rubocop:disable Rails/RakeEnvironment
namespace :gmail do
  desc "Generate the Gmail add-on source for an environment (no push). Usage: rake gmail:build[staging]"
  task :build, [:env] do |_t, args|
    env, config = gmail_env!(args[:env])
    build_dir = gmail_build(env, config)
    puts "\nBuilt #{build_dir}"
    puts "  host: #{config['host']}"
    puts "  name: #{config['display_name']}"
  end

  desc "Build, create-if-needed and push the Gmail add-on. Usage: rake gmail:setup[staging]"
  task :setup, [:env] do |_t, args|
    env, config = gmail_env!(args[:env])

    gmail_preflight!
    build_dir = gmail_build(env, config)
    script_id = gmail_script_id(env, config, build_dir)
    gmail_push(build_dir)

    gmail_next_steps(env, config, script_id)
  end

  # `setup` pushes source, which is all a Test deployment needs — and a Test deployment
  # installs for the script owner and nobody else. Anything a real user installs, whether
  # from the Marketplace or an admin domain-install, runs a *versioned deployment*: a
  # frozen snapshot with its own id. This is the task that cuts one.
  desc "Release the add-on: build, push and cut a versioned deployment. Usage: rake gmail:release[production]"
  task :release, [:env] do |_t, args|
    env, config = gmail_env!(args[:env])

    gmail_preflight!
    revision = gmail_release_guard!(env, config)
    build_dir = gmail_build(env, config)
    script_id = gmail_script_id(env, config, build_dir)
    gmail_push(build_dir)
    deployment_id = gmail_deploy(env, build_dir, revision)

    gmail_release_steps(env, config, script_id, deployment_id)
  end

  desc "List the Apps Script deployments for an environment. Usage: rake gmail:deployments[production]"
  task :deployments, [:env] do |_t, args|
    env, config = gmail_env!(args[:env])
    build_dir = gmail_build(env, config)
    gmail_script_id(env, config, build_dir)
    abort 'clasp deployments failed.' unless system('clasp', 'deployments', chdir: build_dir)
  end

  desc "Print the Apps Script project URL for an environment. Usage: rake gmail:open[staging]"
  task :open, [:env] do |_t, args|
    env, = gmail_env!(args[:env])
    state = gmail_state_path(env)
    abort "No project yet for #{env}. Run: rake gmail:setup[#{env}]" unless File.exist?(state)

    puts "https://script.google.com/d/#{JSON.parse(File.read(state))['scriptId']}/edit"
  end
end
# rubocop:enable Rails/RakeEnvironment

# --- helpers -----------------------------------------------------------------------
# Defined at top level rather than inside the namespace because Rake namespaces are not
# lexical scopes; a method defined inside the block is still a top-level method, and
# nesting it only makes that misleading.

# @return [Array(String, Hash)] the validated environment name and its config
def gmail_env!(name)
  envs = YAML.load_file(GMAIL_ADDON_CONFIG)

  usage = "Usage: rake gmail:setup[<env>]\nEnvironments in #{GMAIL_ADDON_CONFIG}: #{envs.keys.join(', ')}"
  abort usage if name.to_s.empty?

  config = envs[name]
  abort "Unknown environment '#{name}'. Known: #{envs.keys.join(', ')}" if config.nil?

  # A build that silently omits the host would push an add-on that throws on first use.
  %w[display_name host].each do |key|
    abort "#{GMAIL_ADDON_CONFIG}: '#{name}' is missing '#{key}'" if config[key].to_s.strip.empty?
  end

  # Trailing slashes end up concatenated into '//api/v1/...' request paths.
  abort "#{GMAIL_ADDON_CONFIG}: '#{name}' host must not end in '/'" if config['host'].end_with?('/')

  [name, config]
end

# Each environment's build is a complete, self-contained Apps Script project directory.
# clasp pushes whatever is in rootDir, so keeping them separate is what stops a staging
# push from carrying production's manifest.
def gmail_build(env, config)
  build_dir = File.join(GMAIL_ADDON_SRC, 'build', env)
  FileUtils.mkdir_p(build_dir)

  # Hand-written source, copied verbatim — this is the part that must not differ per
  # environment, so that a bug fixed in staging is the same code that reaches production.
  FileUtils.cp(File.join(GMAIL_ADDON_SRC, 'Code.gs'), File.join(build_dir, 'Code.gs'))

  gmail_render('gmail_config.gs.erb', File.join(build_dir, 'Config.gs'), env, config)
  gmail_render('gmail_appsscript.json.erb', File.join(build_dir, 'appsscript.json'), env, config)

  build_dir
end

def gmail_render(template, output_path, env, config)
  template_path = File.join('lib/templates', template)
  # trim_mode '-' matches lib/tasks/outlook_addin.rake so the two generators behave alike.
  rendered = ERB.new(File.read(template_path), trim_mode: '-').result(binding)
  File.write(output_path, rendered)
end

def gmail_state_path(env)
  File.join(GMAIL_ADDON_SRC, ".clasp.#{env}.json")
end

# Resolves this environment's Apps Script project, creating it on first run.
#
# The script id is the identity of the add-on — it is what makes staging and production two
# distinct plugins rather than one that keeps getting overwritten. It is persisted per
# environment (gitignored, since it differs per Google account) and reused on every later
# push.
def gmail_script_id(env, config, build_dir)
  state = gmail_state_path(env)
  live = File.join(build_dir, '.clasp.json')

  if File.exist?(state)
    script_id = JSON.parse(File.read(state))['scriptId']
    File.write(live, JSON.pretty_generate('scriptId' => script_id, 'rootDir' => '.'))
    puts "Reusing #{env} project #{script_id}"
    return script_id
  end

  if ENV['SCRIPT_ID'].to_s.strip.empty?
    puts "\nNo project recorded for '#{env}' — creating one titled #{config['display_name']}..."
    # clasp create writes .clasp.json into the working directory, and refuses to run if one
    # is already there, so it must happen before the reuse path above ever writes one.
    FileUtils.rm_f(live)
    unless system('clasp', 'create', '--type', 'standalone', '--title', config['display_name'], chdir: build_dir)
      abort <<~MSG

        clasp create failed. This is usually one of:
          - the Apps Script API is off — enable it at https://script.google.com/home/usersettings
          - clasp v3 renamed the command; create the project in the browser instead, then
            re-run this task with the id: SCRIPT_ID=<id> rake gmail:setup[#{env}]
      MSG
    end
  else
    File.write(live, JSON.pretty_generate('scriptId' => ENV.fetch('SCRIPT_ID'), 'rootDir' => '.'))
  end

  script_id = JSON.parse(File.read(live))['scriptId']
  # clasp create leaves rootDir unset, which makes later pushes ambiguous; normalise it and
  # record the id outside the build directory, which is disposable.
  File.write(live, JSON.pretty_generate('scriptId' => script_id, 'rootDir' => '.'))
  File.write(state, JSON.pretty_generate('scriptId' => script_id))
  puts "Created #{env} project #{script_id} (recorded in #{state})"

  script_id
end

# Refuses to cut a release that cannot be traced back to a commit, and makes a production
# release an explicit act rather than a typo away.
#
# The whole point of building from config/gmail_addins.yml was that what runs can be
# verified against what is committed. A release from a dirty or unpushed tree breaks that
# guarantee permanently: the deployment is frozen and there is no way to recover which
# source produced it.
#
# @return [String] the revision the release is being cut from
def gmail_release_guard!(env, config)
  dirty = `git status --porcelain`.strip
  unless dirty.empty?
    abort <<~MSG
      Working tree is not clean, so this release could not be traced back to a commit.
      Commit or stash first:

      #{dirty.lines.first(10).map { |l| "  #{l}" }.join}
    MSG
  end

  branch = `git rev-parse --abbrev-ref HEAD`.strip
  local = `git rev-parse HEAD`.strip
  remote = `git rev-parse origin/#{branch} 2>/dev/null`.strip
  unpushed = "HEAD is not pushed to origin/#{branch}. Push first, so the deployed version has a commit anyone can check out."
  abort unpushed if remote.empty? || local != remote

  # A release pointed at a host that is not serving the new code produces an add-on that
  # fails on first use, and versioned deployments cannot be edited in place.
  probe = "curl -sf -o /dev/null --max-time 20 #{config['host']}/manifests/icons/caphive-128.png"
  unreachable = "#{config['host']} is not serving /manifests/icons/caphive-128.png — deploy the Rails app there first."
  abort unreachable unless system(probe)

  # Guarded rather than prompted: rake is a poor place for an interactive confirmation, and
  # an env var is the same ceremony in a terminal and in CI.
  if env.start_with?('production') && ENV['CONFIRM'] != env
    abort <<~MSG
      Refusing to release '#{env}' (#{config['host']}) without an explicit confirmation.
      Re-run with:

        CONFIRM=#{env} rake gmail:release[#{env}]
    MSG
  end

  "#{branch}@#{local[0, 12]}"
end

# Cuts a versioned deployment, reusing this environment's deployment id when one is
# already recorded.
#
# Reuse matters: a Marketplace listing points at one deployment id, so each release must
# update that id rather than mint a new one. Deploying fresh every time would leave the
# published listing frozen on the first release forever.
#
# @return [String] the deployment id
def gmail_deploy(env, build_dir, revision)
  state_path = gmail_state_path(env)
  state = JSON.parse(File.read(state_path))
  description = "#{env} #{revision}"

  cmd = ['clasp', 'deploy', '--description', description]
  if state['deploymentId']
    puts "Updating deployment #{state['deploymentId']}"
    cmd += ['--deploymentId', state['deploymentId']]
  else
    puts 'No deployment recorded yet — creating the first one.'
  end

  output = IO.popen(cmd, chdir: build_dir, err: %i[child out], &:read)
  puts output
  abort 'clasp deploy failed.' unless $CHILD_STATUS.success?

  # clasp prints the deployment id as an AKfycb… token; there is no machine-readable form.
  deployment_id = state['deploymentId'] || output[/AKfycb[A-Za-z0-9_-]+/]
  unreadable = "Deployed, but could not read the deployment id from clasp's output. Run: rake gmail:deployments[#{env}]"
  abort unreadable if deployment_id.nil?

  state['deploymentId'] = deployment_id
  File.write(state_path, JSON.pretty_generate(state))
  deployment_id
end

def gmail_push(build_dir)
  # -f because the build directory is generated: there is never a local edit worth keeping,
  # and without it clasp prompts, which breaks unattended runs.
  abort 'clasp push failed.' unless system('clasp', 'push', '-f', chdir: build_dir)
end

def gmail_preflight!
  abort "clasp not found. Install it with: npm install -g @google/clasp@^2" unless system('which clasp > /dev/null 2>&1')

  # clasp stores its credentials here; without them every command fails with an opaque error.
  return if File.exist?(File.expand_path('~/.clasprc.json'))

  abort 'Not logged in to clasp. Run: clasp login'
end

# The steps that genuinely cannot be scripted. Installing a Gmail add-on is a UI action —
# clasp can create a versioned deployment but not install one into a mailbox — so the task
# stops here rather than pretending to have finished.
def gmail_next_steps(env, config, script_id)
  puts <<~MSG

    Pushed '#{env}' -> #{config['host']}
    Project: https://script.google.com/d/#{script_id}/edit

    Remaining steps (these are UI-only, clasp cannot do them):

      1. Open the project URL above.
      2. Deploy > Test deployments > Install.
      3. Reload Gmail and open any message. "#{config['display_name']}" appears in the
         right-hand side panel.

    The API host is compiled in, so there is no script property to set.
    Check it reaches the server first:

      curl -s -o /dev/null -w "%{http_code}\\n" #{config['host']}/manifests/icons/caphive-128.png

    A Test deployment installs for you only. To put this in front of real users, cut a
    versioned deployment: rake gmail:release[#{env}]
  MSG
end

# What is left after a release. All of it is Google Cloud console and Marketplace listing
# work, none of which clasp can reach.
def gmail_release_steps(env, config, script_id, deployment_id)
  puts <<~MSG

    Released '#{env}' -> #{config['host']}
    Script:     #{script_id}
    Deployment: #{deployment_id}
    Project:    https://script.google.com/d/#{script_id}/edit

    That deployment id is the add-on's identity to Google. Keep it: every later
    `rake gmail:release[#{env}]` updates this same id, which is what a published listing
    points at. It is recorded in #{gmail_state_path(env)}.

    First release only — Marketplace setup, none of which clasp can do:

      1. Attach a standard GCP project (Project Settings > Google Cloud Platform project).
         Apps Script's default project cannot be listed.
      2. In that project: enable the Google Workspace Marketplace SDK, and configure the
         OAuth consent screen with exactly the three scopes in appsscript.json.
      3. Marketplace SDK > App Configuration: point it at deployment #{deployment_id}.
      4. Store Listing: icons, screenshots, a demo video showing each scope in use, and
         privacy policy + terms URLs on a domain verified to you.
      5. Submit for OAuth verification. gmail.addons.current.message.readonly is a
         SENSITIVE scope, so this is a review — expect weeks. It is not RESTRICTED, so no
         CASA security assessment is required.

    Until that review passes, only the script owner and users you share the project with
    can install this. Clients cannot.
  MSG
end
