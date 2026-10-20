# Publishes the deployed revision for the Support Console machine (openspec/changes/support-console,
# design card ⑤ "Code on the machine"): the code Claude reads and the relay/tools bundle, so the
# machine runs what the environment runs. The machine's sync timer picks it up within 5 minutes.
#
# Runs on the deployer's machine (it has git and npm) after every successful deploy and never fails
# a deploy. An environment with no Support Console bucket is skipped by the task itself, so there is
# nothing to enable per stage.
namespace :support_console do
  desc 'Publish the deployed revision to the Support Console machine (non-fatal)'
  task :publish_code do
    env_name = "#{fetch(:stage)}.#{fetch(:env_variant)}" # staging + in -> staging.in
    revision = fetch(:current_revision).to_s
    raise 'no current_revision' if revision.empty?

    run_locally do
      with rev: revision, execute: '1' do
        execute :bundle, :exec, :rake, "support_console:publish_code[#{env_name}]"
      end
    end
  rescue StandardError => e
    puts "  Support Console publish FAILED (deploy unaffected): #{e.message}"
  end
end

after 'deploy:finished', 'support_console:publish_code'
