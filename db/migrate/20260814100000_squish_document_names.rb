# Backfills the whitespace normalization that Document now applies on save.
#
# Document's `normalizes :name` used to `strip`, which only cleaned the ends. A template whose
# own name carried a trailing space (e.g. "SOA ") therefore produced a DOUBLED space in every
# document generated from it, because DocumentGeneratorBase#upload interpolates
# "#{doc_template.name} #{start_date} to #{end_date} - #{model}". HTML collapses that run, so
# the name looked correct everywhere in the UI while exact/LIKE matching silently missed it —
# which is how a CustomNotification's attachment_names stopped attaching a document that was
# visibly right there.
#
# The normalizer is now `squish`, so new and re-saved documents are clean. This migration
# closes the gap for rows written before that change, so DocGenJob's already-exists guards and
# DocumentGeneratorBase#upload's delete-by-exact-name both compare against the same string the
# generator would produce today.
class SquishDocumentNames < ActiveRecord::Migration[8.1]
  # `documents` is one of the very large production tables called out in CLAUDE.md. Without this,
  # the whole full-table sweep runs inside one implicit transaction, holding row locks and growing
  # undo for its entire duration. Disabling it lets each row's UPDATE commit on its own, so the
  # migration is interruptible and never holds a long-lived transaction against that table.
  # Re-running after an interruption is safe — squishing an already-squished name is a no-op,
  # and rows that are already clean are skipped without a write.
  disable_ddl_transaction!

  # Rows are read id+name only: `documents` has wide columns (file_data, text, qna) that would
  # dominate memory if instantiated.
  BATCH_SIZE = 1_000

  def up
    total = 0

    # Live rows only (default scope), NOT unscoped: soft-deleted documents more than double the
    # row count here and nothing reads them — DocGenJob's guards and DocumentGeneratorBase#upload's
    # delete-by-exact-name both query through the default scope, so a deleted row's name can never
    # affect generation or attachment matching.
    #
    # update_all, not save: this deliberately skips validations, callbacks, timestamps and
    # Trackable auditing. A whitespace-only rename is not a business event worth ~1000 audit
    # rows, and the Elasticsearch index is unaffected either way — the analyzer splits on
    # whitespace, so squishing produces exactly the same tokens.
    Document.in_batches(of: BATCH_SIZE) do |batch|
      batch.pluck(:id, :name).each do |id, name|
        next if name.nil?

        squished = name.squish
        next if name == squished

        Document.where(id: id).update_all(name: squished)
        total += 1
      end
    end

    say "Squished #{total} document name(s)"
  end

  # The original whitespace isn't recorded anywhere, so this cannot be undone.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
