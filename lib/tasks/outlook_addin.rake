# frozen_string_literal: true

namespace :outlook do
  desc "Regenerate the per-tenant Outlook add-in manifests in public/manifests/"
  task manifests: :environment do
    require 'erb'
    require 'yaml'

    template_path = Rails.root.join('lib/templates/outlook_manifest.xml.erb')
    tenants = YAML.load_file(Rails.root.join('config/outlook_addins.yml'))
    template = ERB.new(File.read(template_path), trim_mode: '-')

    # Guard against the bug this task exists to prevent: two tenants sharing an add-in id
    # means they cannot be installed side by side, and the second overwrites the first.
    ids = tenants.values.pluck('id')
    duplicates = ids.tally.select { |_id, count| count > 1 }.keys
    raise "Duplicate add-in <Id> across tenants: #{duplicates.join(', ')}" if duplicates.any?

    tenants.each do |tenant, config|
      output_path = Rails.root.join("public/manifests/#{tenant}_outlook_addin.xml")
      File.write(output_path, template.result(binding))
      puts "Wrote #{output_path.relative_path_from(Rails.root)} (#{config['host']})"
    end
  end
end
