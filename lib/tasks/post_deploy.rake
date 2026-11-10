# frozen_string_literal: true

# Checks every post_deploy_steps/*.md file is well-formed (post_deploy_steps/README.md): known environment
# sections, "### <id> — <title>" headings, unique ids, and either steps or a "None — <reason>" line.
# Also run by features/core/post_deploy_steps.feature, so a broken file fails the suite.
namespace :post_deploy do
  desc "Check the format of every post_deploy_steps/*.md file"
  task lint: :environment do
    require Rails.root.join("lib/post_deploy_steps").to_s
    errors = PostDeploySteps.lint(PostDeploySteps.read_dir(Rails.root.join("post_deploy_steps").to_s))
    if errors.empty?
      puts "post_deploy_steps: all files well-formed."
    else
      errors.each { |error| warn error }
      abort "post_deploy_steps: #{errors.size} problem(s)"
    end
  end
end
