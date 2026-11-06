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

  # U12 / R159: plain-words check descriptions into versions published before descriptions existed —
  # text only; a version whose rules differ from its source file is reported and not touched (X94).
  #   bin/rails compliance:backfill_descriptions             # dry run: what would change
  #   EXECUTE=1 bin/rails compliance:backfill_descriptions   # apply (one Audit row per version)
  #   Production also needs FORCE=1.
  desc "Backfill check descriptions into published pack versions (dry-run unless EXECUTE=1)"
  task backfill_descriptions: :environment do
    abort("Refusing in production without FORCE=1") if Rails.env.production? && ENV["FORCE"] != "1"

    sources = Hash.new { |h, k| h[k] = [] }
    Rails.root.glob("db/seeds/compliance/*.json").each do |path|
      data = JSON.parse(File.read(path))
      sources[data.dig("pack", "name")] << data["definition"]
    end
    # The demo's entity pack (lib/tasks/compliance_demo.rake), when that task file is loaded
    if defined?(ComplianceDemoSetup)
      demo = ComplianceDemoSetup.allocate
      sources[ComplianceDemoSetup::CUSTOM_PACK] << demo.send(:custom_definition)
    end

    execute = ENV["EXECUTE"] == "1"
    lines = ComplianceDescriptionBackfill.call(sources:, execute:)
    lines.each { |line| puts line }
    puts "No published version of a known pack found" if lines.empty?
    puts execute ? "Applied." : "Dry run — set EXECUTE=1 to apply"
  end
end
