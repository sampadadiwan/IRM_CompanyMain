# frozen_string_literal: true

# Loads a CapHive compliance pack (JSON under db/seeds/compliance/) as a draft or published version.
# Dry-run by default; EXECUTE=1 applies. Each environment (IN, US) is loaded independently.
#   bin/rails "compliance:load_pack[db/seeds/compliance/sebi_aif_v1.json]"
#   EXECUTE=1 PUBLISH=1 bin/rails "compliance:load_pack[db/seeds/compliance/sebi_aif_v1.json]"
namespace :compliance do
  desc "Load a compliance pack JSON (dry-run unless EXECUTE=1; PUBLISH=1 publishes)"
  task :load_pack, [:path] => :environment do |_t, args|
    data = JSON.parse(File.read(args[:path]))
    errors = ComplianceDefinitionValidator.call(data["definition"], caphive: true)
    puts "Pack: #{data.dig('pack', 'name')} (#{data.dig('pack', 'regime')}) — #{data['definition']['checks'].size} checks, " \
         "#{data['definition']['duties'].size} duties, #{data['definition']['classifications'].size} classifications"
    puts errors.any? ? "Validator: #{errors.join('; ')}" : "Validator: OK"
    next puts("Dry run — set EXECUTE=1 to load") unless ENV["EXECUTE"] == "1"

    abort("Refusing to load an invalid pack") if errors.any?

    version = CompliancePackLoader.call(data, publish: ENV["PUBLISH"] == "1")
    puts "Loaded #{version.compliance_pack.name} #{version.label} (#{version.status})"
  end
end
