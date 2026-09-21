# Prepares incoming_emails for the rewritten Outlook/Gmail add-ins
# (docs/modules/mail_addins/mail_addin_review.md).
#
# Three problems this fixes:
#
# 1. Column sizes. The add-in paths post real mail headers and HTML bodies straight
#    from the client. `body` is TEXT (64KB on MySQL) and real HTML threads exceed that;
#    `to`/`cc_emails` are VARCHAR(255) and overflow on ~8+ recipients; `message_id` is
#    VARCHAR(255) but Outlook was writing an EWS item id into it, which is routinely
#    longer. All three are `Data too long` 500s on MySQL, not silent truncation.
#
# 2. Identity. Outlook wrote a mailbox-specific EWS id and Gmail an account-specific
#    Gmail id into `message_id`, so the same email filed from two clients produced two
#    unrelated rows. `internet_message_id` (the stable RFC 5322 Message-ID) becomes the
#    single dedup key for every path, and gets a unique index scoped to owner.
#
# 3. Matching cost. InvestorEmailMatcher matched domains with `primary_email LIKE
#    '%@domain'`, whose leading wildcard makes any index unusable — a full investors
#    scan on every keystroke-free match request. A dedicated indexed domain column
#    turns that into an equality lookup.
class PrepareIncomingEmailsForMailAddins < ActiveRecord::Migration[8.1]
  # SQLite (test env) has a single unlimited TEXT type and ignores index prefix
  # lengths, so the MySQL-specific widening and key-length options are skipped there.
  # See project memory: test runs SQLite, dev/prod run MySQL.
  def mysql?
    connection.adapter_name.match?(/mysql/i)
  end

  # Migration-local models. The real IncomingEmail/Investor classes carry callbacks,
  # default scopes and validations that would change under us; these see only columns.
  class MigrationIncomingEmail < ActiveRecord::Base
    self.table_name = "incoming_emails"
  end

  class MigrationInvestor < ActiveRecord::Base
    self.table_name = "investors"
  end

  def up
    # --- 1. Column sizes -----------------------------------------------------
    if mysql?
      # MEDIUMTEXT (16MB) comfortably holds a full HTML mail body with quoted history.
      change_column :incoming_emails, :body, :text, size: :medium
      # Recipient lists are unbounded in practice; TEXT removes the 255 ceiling.
      change_column :incoming_emails, :to, :text
      change_column :incoming_emails, :cc_emails, :text
      # Provider-specific ids (EWS item id, Gmail message id) are long and opaque.
      change_column :incoming_emails, :message_id, :text
    end

    # --- 2. Identity ---------------------------------------------------------
    # Backfill from message_id. Every existing row was written by the SendGrid path
    # (the add-ins have never been used against a real mailbox), and that path already
    # extracts the RFC 5322 Message-ID into message_id — so this is a like-for-like copy.
    # Batched per the repo's large-table hygiene rules.
    MigrationIncomingEmail.reset_column_information
    MigrationIncomingEmail.where(internet_message_id: nil).where.not(message_id: nil).in_batches do |batch|
      batch.update_all("internet_message_id = message_id")
    end

    # The unique index below cannot be created over existing duplicates. The SendGrid
    # path already dedups on message_id so there should be none, but a pre-existing
    # duplicate would abort the migration mid-flight. Clear internet_message_id on all
    # but the earliest row of any duplicate group: the row is untouched and still
    # readable, it just stops participating in dedup.
    duplicate_groups = MigrationIncomingEmail
                       .where.not(internet_message_id: nil)
                       .group(:entity_id, :internet_message_id, :owner_type, :owner_id)
                       .having("COUNT(*) > 1")
                       .count

    duplicate_groups.each_key do |entity_id, internet_message_id, owner_type, owner_id|
      scope = MigrationIncomingEmail.where(
        entity_id: entity_id, internet_message_id: internet_message_id,
        owner_type: owner_type, owner_id: owner_id
      )
      keeper_id = scope.minimum(:id)
      cleared = scope.where.not(id: keeper_id).update_all(internet_message_id: nil)
      say "Cleared internet_message_id on #{cleared} duplicate(s) of #{internet_message_id.inspect}, kept id=#{keeper_id}"
    end

    # Dedup key. Scoped to owner as well as entity so that deliberately filing one email
    # against two different investors stays possible, while re-filing the same email to
    # the same owner is caught. NULL internet_message_id (mail with no Message-ID header)
    # repeats freely: both MySQL and SQLite allow multiple NULLs in a unique index.
    # No prefix on internet_message_id: truncating it to 191 chars would make two distinct
    # Message-IDs that agree on their first 191 characters collide, and MailFilingCreate's
    # RecordNotUnique recovery looks the row up by the *full* value — so it would find
    # nothing and the second message could never be filed. The full key fits comfortably:
    # 255+40 utf8mb4 chars plus two bigints is ~1200 bytes against InnoDB's 3072-byte cap.
    # owner_type is still prefixed because it is a wide column holding short class names.
    index_options = { unique: true, name: "idx_incoming_emails_dedup" }
    index_options[:length] = { owner_type: 40 } if mysql?
    add_index :incoming_emails, %i[entity_id internet_message_id owner_type owner_id], **index_options

    # --- 3. Matching ---------------------------------------------------------
    # Lowercased domain part of primary_email, maintained by Investor#sync_primary_email_domain.
    add_column :investors, :primary_email_domain, :string, limit: 191
    add_index :investors, %i[primary_email_domain entity_id], name: "idx_investors_on_email_domain_entity"

    MigrationInvestor.reset_column_information
    # SUBSTRING_INDEX is MySQL-only; SQLite needs the portable substr/instr form.
    domain_sql = if mysql?
                   "LOWER(SUBSTRING_INDEX(primary_email, '@', -1))"
                 else
                   "LOWER(SUBSTR(primary_email, INSTR(primary_email, '@') + 1))"
                 end
    # No default scope here, so soft-deleted investors are backfilled too and are
    # correct immediately if they are ever restored.
    MigrationInvestor.where.not(primary_email: [nil, ""]).where("primary_email LIKE '%@%'").in_batches do |batch|
      batch.update_all("primary_email_domain = #{domain_sql}")
    end
  end

  # Only the additive changes are reversed. Narrowing the widened columns back is
  # deliberately refused: once the add-ins have filed real mail, `body` holds HTML over
  # 64KB and `message_id` holds EWS ids over 255 chars, so re-narrowing either truncates
  # live data or — under MySQL strict mode — raises error 1406 partway through, after the
  # index and column above have already been dropped, leaving a schema that neither `up`
  # nor `down` can complete.
  #
  # Rolling back the *code* does not require narrowing the columns; wider columns are
  # backwards compatible. A deployment that genuinely needs them narrowed should archive
  # the oversized rows first and do it in its own migration.
  def down
    remove_index :investors, name: "idx_investors_on_email_domain_entity"
    remove_column :investors, :primary_email_domain
    remove_index :incoming_emails, name: "idx_incoming_emails_dedup"
  end
end
