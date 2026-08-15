# frozen_string_literal: true

require 'erb'
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
  MSG
end
