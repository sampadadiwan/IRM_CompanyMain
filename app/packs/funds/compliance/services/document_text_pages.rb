# ⑧ Text of a document, page by page, for DocumentFactReader — PDF via pdf-reader (as
# FolderDocumentExtractor does) and plain text (form feeds split pages). Other formats and scans with
# no text layer return no pages, which the reader reports as "Could not read document" without calling
# AI (X45). The file is opened through Shrine into a unique temp dir and removed afterwards.
class DocumentTextPages
  MAX_PAGES = 40
  MAX_CHARS = 60_000

  def self.call(document)
    new(document).call
  end

  def initialize(document)
    @document = document
  end

  def call
    return [] if @document.file_data.blank?

    ext = File.extname(@document.file.original_filename.to_s).downcase
    Dir.mktmpdir("compliance_read_") do |dir|
      path = File.join(dir, "doc#{ext}")
      @document.file.open { |io| File.binwrite(path, io.read) }
      trim(pages_for(path, ext))
    end
  rescue StandardError => e
    Rails.logger.warn("[Compliance] text of document #{@document.id}: #{e.class}")
    []
  end

  private

  def pages_for(path, ext)
    case ext
    when ".pdf"
      require "pdf-reader"
      PDF::Reader.new(path).pages.first(MAX_PAGES).map(&:text)
    when ".txt", ".md"
      File.read(path, encoding: "UTF-8").split("\f").first(MAX_PAGES)
    else
      []
    end
  end

  # Blank pages count for numbering; the whole text is capped so one huge file cannot exhaust the cap
  def trim(pages)
    return [] if pages.all? { |p| p.to_s.strip.empty? }

    budget = MAX_CHARS
    pages.map do |p|
      text = p.to_s.first([budget, 0].max)
      budget -= text.length
      text
    end
  end
end
