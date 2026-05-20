# rake fund_ratios:seed_templates[ENTITY_ID]
#
# Seeds a standard set of FundRatioRunTemplates into the given entity, modelled on the
# templates configured for the "Demo Fund" reference entity (id 157).
#
# Fund names and portfolio company names are resolved at runtime against the target
# entity — items that don't exist are skipped with a warning rather than raising.
# The task is fully idempotent: re-running it will not create duplicates.
#
# Usage:
#   bundle exec rake fund_ratios:seed_templates[42]
#   bundle exec rake fund_ratios:seed_templates[42] ANCHOR=Fund\ A

namespace :fund_ratios do
  desc "Seed standard FundRatioRunTemplates for an entity (modelled on entity 157)"
  task :seed_templates, [:entity_id] => :environment do |_, args|
    entity_id = args[:entity_id]&.to_i
    abort "Usage: rake fund_ratios:seed_templates[ENTITY_ID]" if entity_id.blank?

    entity = Entity.find_by(id: entity_id)
    abort "Entity #{entity_id} not found" unless entity

    # Use the first admin user for the entity as the template owner.
    user = entity.users.joins(:roles).where(roles: { name: "company_admin" }).first ||
           entity.users.first
    abort "No users found for entity #{entity_id}" unless user

    puts "Seeding templates for entity: #{entity.name} (id=#{entity.id})"
    puts "Template owner: #{user.email}"
    puts

    # ── Helpers ────────────────────────────────────────────────────────────────

    # Resolves fund names to ids within the target entity. Warns on any that are missing.
    resolve_funds = ->(names) {
      names.filter_map do |name|
        fund = entity.funds.find_by(name: name)
        warn "  [SKIP] Fund not found: #{name.inspect}" unless fund
        fund&.id
      end
    }

    # Resolves portfolio company names to investor ids within the target entity.
    resolve_pcs = ->(names) {
      names.filter_map do |name|
        pc = entity.investors.find_by(investor_name: name)
        warn "  [SKIP] Portfolio company not found: #{name.inspect}" unless pc
        pc&.id
      end
    }

    # Resolves a single fund by name; returns nil (anchor fund is optional).
    resolve_anchor = ->(name) {
      return nil if name.blank?
      fund = entity.funds.find_by(name: name)
      warn "  [WARN] Anchor fund not found: #{name.inspect} — template will have no anchor" unless fund
      fund
    }

    upsert = ->(attrs) {
      tmpl = FundRatioRunTemplate.find_or_initialize_by(entity: entity, name: attrs[:name])
      is_new = tmpl.new_record?
      tmpl.assign_attributes(attrs.merge(user: user))
      if tmpl.save
        puts "  #{is_new ? 'created' : 'updated '}: #{tmpl.name}"
      else
        warn "  [ERROR] #{tmpl.name}: #{tmpl.errors.full_messages.join(', ')}"
      end
    }

    # ── Template definitions (modelled on entity 157) ─────────────────────────
    #
    # Fund names and portfolio company names are resolved at runtime so this task
    # works for any entity that uses equivalent fund / company names.

    # ── Cross-fund templates ──────────────────────────────────────────────────

    puts "Cross-fund templates:"

    core_fund_names = ["Fund 1", "One", "Growth Fund", "Domestic Opportunities Fund", "New Test Fund"]
    upsert.call(
      name:        "Core Funds — Cross-Fund",
      run_type:    "cross-fund",
      tags:        ["cross-fund"],
      anchor_fund: resolve_anchor.call("Fund 1"),
      fund_ids:    resolve_funds.call(core_fund_names)
    )

    upsert.call(
      name:        "Growth & Credit",
      run_type:    "cross-fund",
      tags:        ["cross-fund"],
      anchor_fund: resolve_anchor.call("Growth Fund"),
      fund_ids:    resolve_funds.call(["Growth Fund", "Credit Fund"])
    )

    quarter_end_fund_names = ["Fund 1", "One", "Credit Fund", "Growth Fund",
                              "Domestic Opportunities Fund", "New Test Fund"]
    upsert.call(
      name:        "Quarter-End — All Funds",
      run_type:    "cross-fund",
      tags:        ["quarter-end", "cross-fund"],
      anchor_fund: resolve_anchor.call("Fund 1"),
      fund_ids:    resolve_funds.call(quarter_end_fund_names)
    )

    upsert.call(
      name:        "Syndicates — Cross-Fund",
      run_type:    "cross-fund",
      tags:        ["cross-fund", "syndicates"],
      anchor_fund: resolve_anchor.call("Syndicate 1"),
      fund_ids:    resolve_funds.call(["Syndicate 1", "Syndicate 2", "Syndicate 3", "Syndicate 4"])
    )

    # ── Cross-portfolio templates ─────────────────────────────────────────────

    puts "Cross-portfolio templates:"

    consumer_pcs = ["AX", "AZ", "Metal Pvt Ltd"]
    upsert.call(
      name:                    "Consumer Portfolio",
      run_type:                "cross-portfolio",
      tags:                    ["cross-portfolio", "consumer"],
      anchor_fund:             resolve_anchor.call("Fund 1"),
      portfolio_company_ids:   resolve_pcs.call(consumer_pcs),
      sectors:                 ["Consumer"]
    )

    upsert.call(
      name:     "DeepTech Portfolio",
      run_type: "cross-portfolio",
      tags:     ["cross-portfolio", "deeptech"],
      anchor_fund: resolve_anchor.call("Fund 1"),
      sectors:  ["DeepTech"]
    )

    upsert.call(
      name:     "Ecommerce Portfolio",
      run_type: "cross-portfolio",
      tags:     ["cross-portfolio", "ecommerce"],
      anchor_fund: resolve_anchor.call("Fund 1"),
      sectors:  ["Ecommerce"]
    )

    fintech_pcs = ["F Pvt Ltd", "E Services"]
    upsert.call(
      name:                  "Fintech & SAAS Portfolio",
      run_type:              "cross-portfolio",
      tags:                  ["cross-portfolio"],
      anchor_fund:           resolve_anchor.call("Fund 1"),
      portfolio_company_ids: resolve_pcs.call(fintech_pcs)
    )

    full_portfolio_pcs = ["AX", "AY", "AZ", "S Pvt Ltd", "B ltd", "F Pvt Ltd", "E Ltd",
                          "R Products Pvt Ltd", "E Services", "Metal Pvt Ltd",
                          "Alternate Pvt Ltd", "One"]
    upsert.call(
      name:                  "Quarter-End — Full Portfolio",
      run_type:              "cross-portfolio",
      tags:                  ["quarter-end", "cross-portfolio"],
      anchor_fund:           resolve_anchor.call("Fund 1"),
      portfolio_company_ids: resolve_pcs.call(full_portfolio_pcs)
    )

    puts
    puts "Done. #{FundRatioRunTemplate.where(entity: entity).count} templates total for #{entity.name}."
  end
end
