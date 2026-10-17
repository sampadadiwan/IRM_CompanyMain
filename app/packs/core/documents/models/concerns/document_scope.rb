module DocumentScope
  extend ActiveSupport::Concern

  # Name pattern (SQL LIKE) of the stray "import archive" documents: older bulk document imports
  # moved Shrine's downloaded copy of the uploaded zip (shrine<yyyymmdd>-<pid>-<rand>.zip) into the
  # folder they then scanned, so the zip itself was saved as a Document. Kept as an audit trail for
  # the fund, but hidden from LPs, who have no use for it.
  IMPORT_ARCHIVE_NAME_LIKE = "shrine%.zip".freeze

  included do
    # Excludes the stray import zips. NULL names are kept explicitly - NOT LIKE alone would drop them.
    scope :not_import_archive, -> { where("documents.name IS NULL OR documents.name NOT LIKE ?", IMPORT_ARCHIVE_NAME_LIKE) }

    scope :for_investor, lambda { |user, entity_id|
      candidates = joins(:access_rights)
                   .merge(AccessRight.access_filter(user))
                   .joins(entity: :investors)
                   # Ensure that the user is an investor and tis investor has been given access rights
                   .where("entities.id=?", entity_id)
                   .where("investors.investor_entity_id=?", user.entity_id)
                   # Ensure this user has investor access
                   .joins(entity: :investor_accesses)
                   .merge(InvestorAccess.approved_for_user(user))
                   # LPs never see the stray import zips (fund users still do, via their own entity scope)
                   .not_import_archive

      # B3 (b): an advisor switched into a client lists only what they can open - see
      # DocumentPolicy.ids_a_switched_advisor_can_open. Everyone else is unchanged.
      # Worked examples B3-1, B3-H — openspec/changes/fix-tenant-isolation-batch2/report.md#verification
      if user.investor_advisor?
        candidates.where(id: DocumentPolicy.ids_a_switched_advisor_can_open(user, candidates))
      else
        candidates
      end
    }

    scope :entity_documents, lambda { |user, entity_id|
      if user.entity_id == entity_id
        where(entity_id:)
      else
        for_investor(user, entity_id)
      end
    }

    scope :owner_documents, lambda { |owner|
      where(owner_id: owner.id, owner_type: owner.class.name)
    }

    # Forgiving search for the documents panel search box (LPs are not expected to know any syntax):
    # every word typed must appear somewhere in the name or the tags, in any order, ignoring case.
    # "q2 statement" matches "Statement - Q2 2026"; a typed * or % is matched literally.
    scope :name_or_tags_matching, lambda { |term|
      # Cap the word count so a pasted paragraph can't build a huge query
      words = term.to_s.split.first(10)
      words.reduce(all) do |relation, word|
        pattern = "%#{sanitize_sql_like(word)}%"
        # Explicit ESCAPE, bound as a param: SQLite (test DB) has no default LIKE escape, and a
        # literal '\\' is quoted differently by MySQL and SQLite
        relation.where("documents.name LIKE :pattern ESCAPE :esc OR documents.tag_list LIKE :pattern ESCAPE :esc",
                       pattern:, esc: "\\")
      end
    }

    scope :templates, -> { where(template: true) }
    scope :not_templates, -> { where(template: false) }
  end
end
