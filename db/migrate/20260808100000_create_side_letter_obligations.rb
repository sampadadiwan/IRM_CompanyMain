# Side Letter Obligation tracking (docs/features/us_gtm/side_letter_obligations.md):
# side letters become structured records anchored on the capital commitment, each
# obligation ("covenant") extracted from them is a reviewable SideLetterObligation,
# and fulfillments/reminders form the audit trail the compliance binder needs.
class CreateSideLetterObligations < ActiveRecord::Migration[8.1]
  def change
    create_table :side_letters do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :capital_commitment, null: false, foreign_key: true
      # The executed side letter PDF — a Document owned by the same commitment
      t.references :document, null: false, foreign_key: true
      t.date :executed_at
      t.string :extraction_status, limit: 20, default: "pending", null: false
      t.text :notes

      t.timestamps
    end

    create_table :side_letter_obligations do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :side_letter, null: false, foreign_key: true
      t.string :obligation_type, limit: 20, null: false
      t.string :title, null: false
      t.text :description
      # Clause citation (e.g. "Section 4.3(b)") — mandatory for AI-extracted rows
      t.string :source_clause, limit: 100
      t.bigint :owner_user_id
      t.string :owner_team, limit: 20
      t.string :trigger_type, limit: 20, null: false
      t.text :trigger_description
      # iCal RRULE for calendar-driven obligations; feeds TaskRecurrenceRule on approval
      t.string :frequency_rrule, limit: 100
      t.date :next_due_date
      # Human review gate: nothing projects tasks/alerts until approved
      t.string :review_status, limit: 20, default: "pending_review", null: false
      t.bigint :reviewed_by_id
      t.datetime :reviewed_at
      # Lifecycle status — set to "active" on approval; nil while pending review
      t.string :status, limit: 20
      t.bigint :task_recurrence_rule_id
      t.integer :reminder_days_before, default: 7, null: false
      t.boolean :mfn_relevant, default: false, null: false
      t.string :mfn_review_status, limit: 25, default: "not_reviewed", null: false
      t.string :extracted_by, limit: 10, default: "manual", null: false
      t.decimal :ai_confidence, precision: 5, scale: 4
      # Re-extraction after an amendment flags changed/new rows for counsel
      t.boolean :delta, default: false, null: false

      t.timestamps
    end
    add_index :side_letter_obligations, :owner_user_id
    add_index :side_letter_obligations, :task_recurrence_rule_id
    add_index :side_letter_obligations, :review_status
    add_index :side_letter_obligations, :next_due_date

    create_table :obligation_fulfillments do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :side_letter_obligation, null: false, foreign_key: true
      t.date :fulfilled_at, null: false
      t.bigint :fulfilled_by_id
      # "method" would shadow Object#method as an AR attribute — hence fulfillment_method
      t.text :fulfillment_method
      t.string :period_covered, limit: 40
      # Optional evidence document + the projected task that recorded this fulfillment
      t.bigint :document_id
      t.bigint :task_id

      t.timestamps
    end
    add_index :obligation_fulfillments, :task_id

    create_table :obligation_reminders do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :side_letter_obligation, null: false, foreign_key: true
      # upcoming | due | overdue — one row per alert actually sent (idempotency log)
      t.string :kind, limit: 10, null: false
      t.date :due_date
      t.bigint :task_id
      t.bigint :recipient_user_id
      t.datetime :sent_at

      t.timestamps
    end
    # Idempotency lookup: "has an alert of this kind gone out for this task's due date?"
    add_index :obligation_reminders, %i[side_letter_obligation_id kind due_date],
              name: "idx_obligation_reminders_dedup"
  end
end
