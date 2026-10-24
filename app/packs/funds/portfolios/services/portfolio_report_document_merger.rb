require "fileutils"

# Joins the parts of one portfolio report run into a single .docx, stored under a shared
# "/Portfolio Reports/Generated Portfolio Reports" folder. The sources are already in their final order
# (the run decides it): a source is either a company's generated Document or the path of a
# temporary .docx built for a consolidated report. Each company's own individually generated
# document is left exactly where PortfolioReportDocGenerator already put it - this is purely
# an additional artifact, not a replacement.
class PortfolioReportDocumentMerger
  # @param sources [Array<Document, String>] Documents or .docx paths, in the order they appear in the result.
  # @param portfolio_report [PortfolioReport] The run's first report (gives the entity).
  # @param template [Document, nil] The first row's template: names the file and gives its settings.
  # @param company_count [Integer] How many companies the run was for (shown in the name).
  # @return [Document] The saved combined document.
  def self.call(sources, portfolio_report:, template:, company_count:, start_date:, end_date:, user_id:)
    new(sources, portfolio_report:, template:, company_count:, start_date:, end_date:, user_id:).call
  end

  def initialize(sources, portfolio_report:, template:, company_count:, start_date:, end_date:, user_id:)
    @sources = sources
    @portfolio_report = portfolio_report
    @template = template
    @company_count = company_count
    @start_date = start_date
    @end_date = end_date
    @user_id = user_id
  end

  def call
    entity = @portfolio_report.entity
    template = @template

    working_dir = Rails.root.join("tmp", "portfolio_report_merge", SecureRandom.hex(8)).to_s
    FileUtils.mkdir_p(working_dir)

    # Only the files downloaded here are deleted below; paths handed in belong to the caller
    downloaded_paths = []
    paths = @sources.map do |source|
      next source if source.is_a?(String)

      downloaded_paths << source.file.download.path
      downloaded_paths.last
    end
    merged_path = File.join(working_dir, "merged.docx")
    DocxMerger.merge(paths, merged_path)

    folder = find_or_create_folder(entity, ["Portfolio Reports"], "Generated Portfolio Reports")

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
      name: "#{template&.name} #{@start_date} to #{@end_date} - #{@company_count} companies",
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
