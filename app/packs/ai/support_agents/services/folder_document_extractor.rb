# frozen_string_literal: true

# Downloads documents from a Shrine-backed Folder and extracts text for LLM context.
# Reuses the same extraction logic as GenerateSectionContentJob but in a
# request-safe way (unique temp dir per call, auto-cleaned up).
#
# @example
#   context = FolderDocumentExtractor.extract(folder)
#   # => "=== Document: pitch.pdf ===\n..."
class FolderDocumentExtractor
  SUPPORTED_EXTENSIONS = %w[.pdf .txt .md .xlsx .xls .pptx .ppt].freeze
  MAX_DOCUMENTS = 10
  MAX_CHARS_PER_DOC = 5000

  # @param folder [Folder] the folder whose documents to extract
  # @return [String] formatted document context for LLM consumption
  def self.extract(folder)
    new(folder).extract
  end

  def initialize(folder)
    @folder = folder
  end

  def extract
    return "" if @folder.nil?

    context = ""
    Dir.mktmpdir("portfolio_chat_") do |tmp_dir|
      download_documents(tmp_dir)
      context = load_and_format(tmp_dir)
    end
    context
  end

  private

  def download_documents(tmp_dir)
    count = 0
    @folder.documents.each do |doc|
      break if count >= MAX_DOCUMENTS
      next if doc.file.blank?

      filename  = File.basename(doc.file.original_filename.to_s).gsub(/[^0-9A-Za-z.\-_]/, '_')
      extension = File.extname(filename).downcase
      next unless SUPPORTED_EXTENSIONS.include?(extension)

      file_path = File.join(tmp_dir, filename)
      doc.file.open { |io| File.binwrite(file_path, io.read) }
      count += 1
      Rails.logger.info "[FolderDocumentExtractor] Downloaded: #{filename}"
    rescue StandardError => e
      Rails.logger.warn "[FolderDocumentExtractor] Skipped #{doc.name}: #{e.message}"
    end
  end

  def load_and_format(tmp_dir)
    documents = []

    Dir.glob(File.join(tmp_dir, "*")).each do |file_path|
      next unless File.file?(file_path)

      extension = File.extname(file_path).downcase
      next unless SUPPORTED_EXTENSIONS.include?(extension)

      text = extract_text(file_path, extension)
      documents << { name: File.basename(file_path), content: text.to_s.first(MAX_CHARS_PER_DOC) }
      break if documents.size >= MAX_DOCUMENTS
    rescue StandardError => e
      Rails.logger.warn "[FolderDocumentExtractor] Extraction failed #{file_path}: #{e.message}"
    end

    format_for_llm(documents)
  end

  def extract_text(file_path, extension)
    case extension
    when '.txt', '.md' then File.read(file_path, encoding: 'UTF-8')
    when '.pdf'        then extract_pdf(file_path)
    when '.xlsx', '.xls' then extract_excel(file_path)
    when '.pptx', '.ppt' then extract_pptx(file_path)
    end
  end

  def extract_pdf(file_path)
    require 'pdf-reader'
    PDF::Reader.new(file_path).pages.first(20).map(&:text).join("\n\n")
  rescue StandardError => e
    "Error extracting PDF: #{e.message}"
  end

  def extract_excel(file_path)
    require 'roo'
    spreadsheet = Roo::Spreadsheet.open(file_path)
    parts = spreadsheet.sheets.first(5).map do |sheet_name|
      sheet = spreadsheet.sheet(sheet_name)
      rows  = []
      sheet.each_row_streaming(pad_cells: true, max_rows: 100) do |row|
        vals = row.map { |c| c&.value.to_s.strip }.compact_blank
        rows << vals.join(" | ") if vals.any?
      end
      "=== Sheet: #{sheet_name} ===\n#{rows.join("\n")}"
    end
    parts.join("\n\n")
  rescue StandardError => e
    "Error extracting Excel: #{e.message}"
  end

  def extract_pptx(file_path)
    require 'zip'
    require 'nokogiri'
    parts = []
    Zip::File.open(file_path) do |zip|
      zip.glob('ppt/slides/slide*.xml')
         .sort_by { |e| e.name.match(/slide(\d+)\.xml/)[1].to_i }
         .first(30)
         .each_with_index do |entry, i|
        doc = Nokogiri::XML(entry.get_input_stream.read).tap(&:remove_namespaces!)
        texts = doc.xpath('//t').map(&:text).compact_blank
        parts << "=== Slide #{i + 1} ===\n#{texts.join("\n")}" if texts.any?
      end
    end
    parts.join("\n\n").presence || "No text found in PowerPoint"
  rescue StandardError => e
    "Error extracting PPTX: #{e.message}"
  end

  def format_for_llm(documents)
    return "No documents found in folder." if documents.empty?

    documents.map { |d| "=== Document: #{d[:name]} ===\n#{d[:content]}\n" }.join("\n---\n\n")
  end
end
