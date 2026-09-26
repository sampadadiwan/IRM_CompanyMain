# Repairs the fallout of the "Full path combination must be unique" bug (25 Sep 2026).
#
# WithFolder#setup_document_folder used to write the owner -> folder pointer with a bare
# `save`, which silently failed for any owner that was not yet valid (an InvestorKyc is
# created with `validate: false` while PAN/address/bank details are blank). The Folder row was
# written and stamped with `owner`, but document_folder_id stayed NULL -- so the next touch
# created *another* folder for the same owner. Once the owner became valid it latched onto one
# of the twins, and the first rename after that tried to move it onto the other's path.
#
# The code fix stops new duplicates forming. This task cleans up what is already there:
#
#   1. orphaned links -- owner owns a folder but document_folder_id is NULL
#   2. twins          -- two folders with the same owner under the same parent
#
# Usage:
#   bundle exec rake folders:report                    # count both problems, change nothing
#   bundle exec rake folders:repair                    # fix them
#   bundle exec rake folders:repair TYPE=InvestorKyc   # one owner type only
#   bundle exec rake folders:repair DRY_RUN=true       # list what would change and stop
#
# Repair is idempotent and safe to re-run. Twins are merged by UpdateDocumentFolderPathJob
# itself (run inline here), so the task and the live code path share one definition of
# "merge": documents and children move into the folder that already holds the wanted path,
# the owner is repointed at it, and the emptied duplicate is soft-deleted.
namespace :folders do
  desc "Report owners whose document_folder link is missing or duplicated"
  task report: :environment do
    FolderDuplicateRepair.new(type: ENV.fetch("TYPE", nil), dry_run: true).call
  end

  desc "Backfill missing document_folder links and merge duplicate owner folders"
  task repair: :environment do
    FolderDuplicateRepair.new(type: ENV.fetch("TYPE", nil), dry_run: ENV["DRY_RUN"] == "true").call
  end
end

# Kept in the rake file rather than app/ on purpose: this is one-off remediation, not a
# behaviour of the app. Delete it once production is clean.
class FolderDuplicateRepair
  def initialize(type: nil, dry_run: false)
    @type = type
    @dry_run = dry_run
    @linked = 0
    @merged = 0
    @failed = []
  end

  def call
    owner_types.each { |owner_type| repair_type(owner_type) }
    report
  end

  private

  attr_reader :type, :dry_run

  # Straight from the data: whatever actually owns folders today. distinct in SQL, not uniq in
  # Ruby -- folders is a large table.
  def owner_types
    return [type] if type.present?

    Folder.where.not(owner_type: nil).distinct.pluck(:owner_type).sort
  end

  def repair_type(owner_type)
    klass = owner_type.safe_constantize
    return unless repairable?(klass)

    backfill_links(klass, owner_type)
    merge_twins(klass, owner_type)
  end

  # Folders can be owned by anything that includes WithFolder; skip anything that does not
  # carry the pointer column or cannot name its own path.
  def repairable?(klass)
    klass.present? &&
      klass.respond_to?(:column_names) &&
      klass.column_names.include?("document_folder_id") &&
      klass.method_defined?(:folder_path)
  end

  # (1) The owner owns a folder but does not point at it. Adopt the folder the owner would
  # have adopted had the original save worked.
  def backfill_links(klass, owner_type)
    owners_missing_link(klass, owner_type).find_each do |owner|
      folder = owner.adoptable_owned_folder(owner.folder_path)
      next if folder.nil?

      log "link #{owner_type} #{owner.id} -> folder #{folder.id} (#{folder.full_path})"
      next if dry_run

      owner.update_column(:document_folder_id, folder.id) # rubocop:disable Rails/SkipsModelValidations
      @linked += 1
    end
  end

  # (2) Two folders, one owner, one parent. Hand it to the job, which merges and then renames.
  def merge_twins(klass, owner_type)
    twin_owner_ids(owner_type).each_slice(500) do |ids|
      klass.where(id: ids).find_each do |owner|
        log "merge twins for #{owner_type} #{owner.id}"
        next if dry_run

        UpdateDocumentFolderPathJob.perform_now(owner_type, owner.id)
        @merged += 1
      rescue StandardError => e
        @failed << "#{owner_type} #{owner.id}: #{e.message}"
      end
    end
  end

  # Owners that own a folder but do not point at one. find_each in the caller, so this stays a
  # relation -- the candidate set spans every WithFolder model and some of them are large.
  def owners_missing_link(klass, owner_type)
    klass.where(document_folder_id: nil)
         .where(id: Folder.where(owner_type:).where.not(owner_id: nil).select(:owner_id))
  end

  # Owner ids with more than one folder under the same parent -- the duplicate signature.
  # DISTINCT in SQL rather than .uniq in Ruby; folders is a large table.
  def twin_owner_ids(owner_type)
    Folder.where(owner_type:)
          .where.not(owner_id: nil)
          .group(:owner_id, :ancestry)
          .having("COUNT(*) > 1")
          .distinct
          .pluck(:owner_id)
  end

  def log(message)
    puts(dry_run ? "[dry run] #{message}" : message)
  end

  def report
    puts "\nlinked: #{@linked}, merged: #{@merged}, failed: #{@failed.size}"
    @failed.each { |line| puts "  FAILED #{line}" }
  end
end
