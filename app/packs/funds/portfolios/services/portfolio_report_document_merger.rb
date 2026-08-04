require "fileutils"

# Merges the same-template documents generated for multiple portfolio companies (in one
# PortfolioReportJob run) into a single .docx, stored under a shared
# "/Investors/Generated Portfolio Reports" folder. Each company's own individually generated
# document is left exactly where PortfolioReportDocGenerator already put it — this is purely
# an additional artifact, not a replacement.
class PortfolioReportDocumentMerger
  def self.call(docs, portfolio_report:, start_date:, end_date:, user_id:)
    new(docs, portfolio_report:, start_date:, end_date:, user_id:).call
  end

  def initialize(docs, portfolio_report:, start_date:, end_date:, user_id:)
    @docs = docs
    @portfolio_report = portfolio_report
    @start_date = start_date
    @end_date = end_date
    @user_id = user_id
  end

  def call
    entity = @portfolio_report.entity
    template = @docs.first.from_template

    # Merge the companies' reports in a consistent alphabetical order (by company) so the combined
    # document reads the same way every time, regardless of the order the batch generated them in.
    ordered_docs = @docs.sort_by { |doc| doc.owner.to_s.downcase }

    working_dir = Rails.root.join("tmp", "portfolio_report_merge", SecureRandom.hex(8)).to_s
    FileUtils.mkdir_p(working_dir)

    downloaded_paths = ordered_docs.map { |doc| doc.file.download.path }
    merged_path = File.join(working_dir, "merged.docx")
    DocxMerger.merge(downloaded_paths, merged_path)

    folder = find_or_create_folder(entity, %w[Investors], "Generated Portfolio Reports")

    # Carry the same document settings each individual company report gets from the template
    # (see DocumentGeneratorBase#upload): original/download/printing permissions, esign ordering,
    # the "Generated" owner tag and the from_template link. We deliberately skip display_on_page
    # and e-signatures — those are per-company concerns that don't apply to the combined deck.
    template_settings = template&.attributes&.slice("orignal", "download", "printing", "force_esign_order") || {}
    document = Document.new(template_settings)
    document.assign_attributes(
      entity_id: entity.id,
      folder: folder,
      user_id: @user_id,
      # Same "<template> <start> to <end> - ..." shape as each individual company document.
      name: "#{template&.name} #{@start_date} to #{@end_date} - #{@docs.size} companies",
      from_template: template,
      owner_tag: "Generated",
      owner: nil,
      tag_list: "Portfolio Report"
    )
    document.file = File.open(merged_path, "rb")
    document.save!
    document
  ensure
    downloaded_paths&.each { |path| FileUtils.rm_f(path) }
    FileUtils.rm_rf(working_dir) if working_dir
  end

  private

  def find_or_create_folder(entity, *path_segments)
    parent = entity.root_folder
    path_segments.flatten.each do |name|
      parent = parent.children.where(entity_id: entity.id, name: name).first_or_create!
    end
    parent
  end
end
