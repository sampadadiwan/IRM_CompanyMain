# Allocation Run Templates and Groups — see docs/business_requirements/allocation_run_sequences.md.
#
# An AllocationRunTemplate is one fund plus the parameters it is always run with (everything on
# the allocation screen except the period). A group is an ordered list of templates run one
# after another with one period. Every group run is recorded per template so a worker restart
# resumes from the template that was running, and so "resume from failed template" can skip
# the ones that already succeeded (decisions 8 and 9).
class CreateAllocationRunTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :allocation_run_templates do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :fund, null: false, foreign_key: true
      t.string :name, limit: 100, null: false
      t.text :description
      # Run parameters: every option on the allocation screen is carried, including the
      # explain and sample debugging aids (decision 14, option a).
      t.string :rule_for, limit: 10 # "Accounting", "Reporting" or nil for both
      t.string :tag_list # comma-separated formula tags, same shape as allocation_runs.tag_list
      t.boolean :run_allocations, default: true, null: false
      t.boolean :generate_soa, default: false, null: false
      t.string :statement_for, limit: 20
      # A reference to the statement document itself, not its name (decision 15): a renamed
      # document must fail the pre-run check rather than silently produce no statements.
      t.references :statement_document, foreign_key: { to_table: :documents }
      t.boolean :fund_ratios, default: false, null: false
      t.boolean :explain, default: false, null: false
      t.boolean :sample, default: false, null: false
      t.timestamps
    end
    add_index :allocation_run_templates, %i[entity_id name], unique: true

    create_table :allocation_run_template_groups do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :name, limit: 100, null: false
      t.text :description
      t.timestamps
    end
    add_index :allocation_run_template_groups, %i[entity_id name], unique: true

    # Ordered membership: one row per template per group, position is the run order.
    create_table :allocation_run_template_group_items do |t|
      t.references :allocation_run_template_group, null: false, foreign_key: true, index: { name: "idx_atg_items_on_group" }
      t.references :allocation_run_template, null: false, foreign_key: true, index: { name: "idx_atg_items_on_template" }
      t.integer :position, null: false, default: 1
      t.timestamps
    end
    add_index :allocation_run_template_group_items, %i[allocation_run_template_group_id allocation_run_template_id],
              unique: true, name: "idx_atg_items_unique_template_per_group"

    # One row per time a group is run. The group reference is nullable and the name is
    # snapshotted so history outlives a deleted group (decision 17).
    create_table :allocation_group_runs do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :allocation_run_template_group, foreign_key: true, index: { name: "idx_agr_on_group" }
      t.string :group_name, limit: 100, null: false
      t.date :start_date, null: false
      t.date :end_date, null: false
      # queued -> running -> success | failed
      t.string :status, limit: 20, null: false, default: "queued"
      t.text :message
      # When "resume from failed template" was used, the earlier run whose successes were reused.
      t.references :resumed_from, foreign_key: { to_table: :allocation_group_runs }
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :allocation_group_runs, %i[entity_id status]

    # One row per template in a group run, in run order. Carries the template name and fund
    # so the row still reads correctly after the template is deleted.
    create_table :allocation_group_run_items do |t|
      t.references :allocation_group_run, null: false, foreign_key: true, index: { name: "idx_agr_items_on_run" }
      t.references :allocation_run_template, foreign_key: true, index: { name: "idx_agr_items_on_template" }
      t.references :fund, null: false, foreign_key: true
      t.references :allocation_run, foreign_key: true
      t.string :template_name, limit: 100, null: false
      t.integer :position, null: false
      # pending -> running -> success | failed | skipped (not reached) | reused (resume kept an earlier success)
      t.string :status, limit: 20, null: false, default: "pending"
      t.text :message
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
  end
end
