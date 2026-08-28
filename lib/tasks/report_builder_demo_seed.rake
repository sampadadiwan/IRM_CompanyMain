namespace :report_builder_demo do
  desc <<~DESC
    Load 5 complex Report Builder reports into an entity, to demo the feature's
    capabilities (multi-join zero-fill, every aggregate type, pivot tables,
    computed formula columns, Ransack filters on root and joined scopes, and
    both SQL-level and computed sorting).

    Idempotent — re-running replaces each report's columns/template so you can
    tweak this file and re-seed without piling up duplicates.

    Usage:
      rails "report_builder_demo:seed[157]"   # entity id (quote required in zsh)

    After running, open Reports in the app for that entity — the 5 reports
    are named below and marked "shared" so any entity user can see them.
  DESC
  task :seed, [:entity_id] => :environment do |_, args|
    abort "[report_builder_demo:seed] Usage: rails report_builder_demo:seed[entity_id]" unless args[:entity_id]

    entity = Entity.find_by(id: args[:entity_id].to_i)
    abort "[report_builder_demo:seed] Entity #{args[:entity_id]} not found." unless entity

    user = User.where(entity_id: entity.id).first
    abort "[report_builder_demo:seed] Entity #{entity.id} has no users — cannot set user on Report." unless user

    puts "[report_builder_demo:seed] Seeding for entity #{entity.id} (#{entity.name}), user #{user.email}"
    puts

    # Ransack filter value — computed at run time rather than hard-coded so the
    # "recent capital calls" filter in report 3 never goes stale.
    three_years_ago = (Time.zone.today - 3.years).iso8601

    # ── Report definitions ──────────────────────────────────────────────────
    # Each entry mirrors what ReportBuilderController#create / #update_template
    # / #add_column persist — a Report#template JSON blob (joins, aggregates,
    # root_filters, sort, formulas, currency) plus one GridViewPreference per
    # selected column. Formula columns are NOT GridViewPreference rows — the
    # query engine appends them automatically from template["formulas"].

    reports = [
      {
        name: "LP Commitment & Capital Activity Summary",
        description: "One row per investor: committed/called/collected/distributed capital " \
                     "rolled up from all their commitments, latest KYC/AML status, and an " \
                     "uncalled-commitment formula column. Demonstrates two simultaneous " \
                     "has-many joins with zero-row fill, sum/count/latest aggregates, a " \
                     "computed formula column, and sorting by a joined (non-SQL) column.",
        template: {
          root_model: "Investor",
          joins: [
            { relation: "capital_commitments", model: "CapitalCommitment", include_zero_rows: true },
            { relation: "investor_kycs", model: "InvestorKyc", include_zero_rows: true }
          ],
          aggregates: {
            "capital_commitments.committed_amount" => "sum",
            "capital_commitments.call_amount" => "sum",
            "capital_commitments.collected_amount" => "sum",
            "capital_commitments.distribution_amount" => "sum",
            "capital_commitments.id" => "count",
            "investor_kycs.verified" => "latest",
            "investor_kycs.aml_status" => "latest"
          },
          root_filters: {},
          sort: { key: "capital_commitments.committed_amount", dir: "desc" },
          formulas: [
            { key: "formula_uncalled_commitment", label: "Uncalled Commitment",
              expression: "[capital_commitments.committed_amount] - [capital_commitments.call_amount]" }
          ]
        },
        columns: [
          ["investor_name; text-col", "Investor Name"],
          ["tag_list; text-col", "Tags"],
          ["city; text-col", "City"],
          ["capital_commitments.committed_amount; num-col", "Total Committed"],
          ["capital_commitments.call_amount; num-col", "Total Called"],
          ["capital_commitments.collected_amount; num-col", "Total Collected"],
          ["capital_commitments.distribution_amount; num-col", "Total Distributed"],
          ["capital_commitments.id; num-col", "# Commitments"],
          ["investor_kycs.verified; text-col", "KYC Verified"],
          ["investor_kycs.aml_status; text-col", "AML Status"]
        ]
      },
      {
        name: "KYC & AML Compliance Register",
        description: "One row per KYC record, with each investor's commitment totals, the " \
                     "spread of unit types they hold, and their earliest commitment date " \
                     "rolled up from their commitments. Filtered to AML 'potential_match' " \
                     "records. Demonstrates the list/min aggregates and a percentage formula.",
        template: {
          root_model: "InvestorKyc",
          joins: [
            { relation: "capital_commitments", model: "CapitalCommitment", include_zero_rows: true }
          ],
          aggregates: {
            "capital_commitments.committed_amount" => "sum",
            "capital_commitments.call_amount" => "sum",
            "capital_commitments.unit_type" => "list",
            "capital_commitments.id" => "count",
            "capital_commitments.commitment_date" => "min"
          },
          root_filters: { aml_status_eq: "potential_match" },
          sort: { key: "verified", dir: "asc" },
          formulas: [
            { key: "formula_call_coverage_pct", label: "Call Coverage %",
              expression: "([capital_commitments.call_amount] / [capital_commitments.committed_amount]) * 100" }
          ]
        },
        columns: [
          ["investor_name; text-col", "Investor"],
          ["full_name; text-col", "Investing Entity"],
          ["kyc_type; text-col", "KYC Type"],
          ["verified; text-col", "KYC Verified"],
          ["aml_status; text-col", "AML Status"],
          ["capital_commitments.committed_amount; num-col", "Total Committed"],
          ["capital_commitments.call_amount; num-col", "Total Called"],
          ["capital_commitments.unit_type; text-col", "Unit Types Held"],
          ["capital_commitments.id; num-col", "# Commitments"],
          ["capital_commitments.commitment_date; date-col", "Earliest Commitment Date"]
        ]
      },
      {
        name: "Capital Call Collection Waterfall",
        description: "One row per capital call (last 3 years) with a pivoted breakdown of " \
                     "collected remittance amounts by status (Paid / Pending / Overdue) as " \
                     "cross-tab columns. Demonstrates the pivot-table capability and a " \
                     "root-level date-range filter.",
        template: {
          root_model: "CapitalCall",
          joins: [
            { relation: "capital_remittances", model: "CapitalRemittance", include_zero_rows: true,
              pivot: { group_bys: ["status"], value_col: "collected_amount", aggregate: "sum" } }
          ],
          aggregates: {},
          root_filters: { due_date_gteq: three_years_ago },
          sort: { key: "due_date", dir: "desc" },
          formulas: []
        },
        columns: [
          ["name; text-col", "Capital Call"],
          ["due_date; date-col", "Due Date"],
          ["call_amount; num-col", "Call Amount"],
          ["collected_amount; num-col", "Collected Amount"],
          ["due_amount; num-col", "Outstanding"],
          ["approved; text-col", "Approved"]
        ]
      },
      {
        name: "Distribution Payment Reconciliation",
        description: "Completed distribution payments with gross vs. net payable and two " \
                     "computed formula columns (fee deducted, fee %). Demonstrates multiple " \
                     "root-level Ransack predicates (eq + gt) with no joins at all.",
        template: {
          root_model: "CapitalDistributionPayment",
          joins: [],
          aggregates: {},
          root_filters: { completed_eq: "true", net_payable_gt: 0 },
          sort: { key: "payment_date", dir: "desc" },
          formulas: [
            { key: "formula_fee_deducted", label: "Fee Deducted",
              expression: "[gross_payable] - [net_payable]" },
            { key: "formula_fee_pct", label: "Fee %",
              expression: "(([gross_payable] - [net_payable]) / [gross_payable]) * 100" }
          ]
        },
        columns: [
          ["investing_entity_name; text-col", "Investing Entity"],
          ["folio_id; text-col", "Folio No"],
          ["gross_payable; num-col", "Gross Payable"],
          ["net_payable; num-col", "Net Payable"],
          ["payment_date; date-col", "Payment Date"],
          ["completed; text-col", "Completed"]
        ]
      },
      {
        name: "Fund-Level Commitment & Call Activity Dashboard",
        description: "One row per non-snapshot fund, with commitment totals rolled up from " \
                     "capital_commitments and call activity (count, average size, most " \
                     "recent due date) rolled up from capital_calls. Demonstrates two " \
                     "independent has-many joins on the same root, the avg/max aggregates, " \
                     "and the report currency label.",
        template: {
          root_model: "Fund",
          joins: [
            { relation: "capital_commitments", model: "CapitalCommitment", include_zero_rows: true },
            { relation: "capital_calls", model: "CapitalCall", include_zero_rows: true }
          ],
          aggregates: {
            "capital_commitments.committed_amount" => "sum",
            "capital_commitments.call_amount" => "sum",
            "capital_commitments.collected_amount" => "sum",
            "capital_commitments.distribution_amount" => "sum",
            "capital_calls.id" => "count",
            "capital_calls.call_amount" => "avg",
            "capital_calls.due_date" => "max"
          },
          root_filters: { snapshot_eq: "false" },
          sort: { key: "name", dir: "asc" },
          formulas: [],
          currency: entity.currency
        },
        columns: [
          ["name; text-col", "Fund"],
          ["category; text-col", "Category"],
          ["tag_list; text-col", "Tags"],
          ["capital_commitments.committed_amount; num-col", "Total Committed"],
          ["capital_commitments.call_amount; num-col", "Total Called"],
          ["capital_commitments.collected_amount; num-col", "Total Collected"],
          ["capital_commitments.distribution_amount; num-col", "Total Distributed"],
          ["capital_calls.id; num-col", "# Capital Calls"],
          ["capital_calls.call_amount; num-col", "Avg Call Size"],
          ["capital_calls.due_date; date-col", "Last Call Due Date"]
        ]
      }
    ]

    # ── Create / update each report ─────────────────────────────────────────

    reports.each do |spec|
      report = Report.find_or_initialize_by(entity_id: entity.id, user_id: user.id, name: spec[:name], report_builder: true)
      report.assign_attributes(
        curr_role: user.curr_role.presence || "employee",
        description: spec[:description],
        url: report.persisted? ? report.url : "/report_builder",
        report_builder: true,
        shared: true,
        template: spec[:template]
      )
      report.save!

      # Idempotent column rebuild — mirrors ReportBuilderController#apply_template.
      report.grid_view_preferences.destroy_all
      spec[:columns].each_with_index do |(key, label), i|
        report.grid_view_preferences.create!(
          key: key,
          name: label,
          label: label,
          entity_id: entity.id,
          sequence: i + 1
        )
      end

      status = report.previously_new_record? ? "created" : "updated"
      puts "  [#{status}] Report id=#{report.id} '#{report.name}' (#{spec[:columns].size} columns)"
    end

    puts
    puts "=" * 60
    puts "Seed complete for entity #{entity.id} (#{entity.name})."
    puts "Open /reports to see the 5 seeded reports (marked shared)."
    puts "=" * 60
  end
end
