require "hexapdf"

class PdfAccessibilityService
  def self.verify_pdf_accessibility(pdf_path, user_id)
    return if user_id.blank?

    if File.extname(pdf_path).downcase != ".pdf"
      msg = "File is not a PDF: #{pdf_path}"
      Rails.logger.error { msg }
      # UserAlert.new(user_id:, message: msg, level: "error").broadcast
      raise msg
    end

    unless File.exist?(pdf_path)
      msg = "File does not exist: #{pdf_path}"
      Rails.logger.error { msg }
      # UserAlert.new(user_id:, message: msg, level: "error").broadcast
      raise msg
    end

    doc = HexaPDF::Document.open(pdf_path)
    info = doc.trailer[:Info] || {}
    viewer_prefs = doc.catalog[:ViewerPreferences] || {}
    xmp_stream = doc.catalog[:Metadata]

    results = {
      # Accessibility Structure
      has_language: false,
      has_mark_info: false,
      has_struct_tree: false,
      struct_tree_elements: 0,
      pages_with_marked_content: 0,
      total_pages: doc.pages.size,
      # Document Metadata
      has_title: false,
      has_author: false,
      has_subject: false,
      has_keywords: false,
      has_creator: false,
      has_producer: false,
      has_creation_date: false,
      has_mod_date: false,
      # Document Settings
      has_display_doc_title: false,
      # XMP Metadata
      has_xmp_stream: false,
      has_xmp_pdfua_identification: false,
      has_xmp_dc_title: false,
      xmp_conformance_level: nil,
      is_truly_accessible: false
    }

    # Check accessibility structure
    results[:has_language] = doc.catalog[:Lang].present?
    results[:has_mark_info] = doc.catalog[:MarkInfo].present?
    results[:has_struct_tree] = doc.catalog[:StructTreeRoot].present?

    # Check document metadata
    results[:has_title] = info[:Title].present?
    results[:has_author] = info[:Author].present?
    results[:has_subject] = info[:Subject].present?
    results[:has_keywords] = info[:Keywords].present?
    results[:has_creator] = info[:Creator].present?
    results[:has_producer] = info[:Producer].present?
    results[:has_creation_date] = info[:CreationDate].present?
    results[:has_mod_date] = info[:ModDate].present?

    # Check viewer preferences
    results[:has_display_doc_title] = viewer_prefs[:DisplayDocTitle].present?

    # Check XMP metadata stream
    if xmp_stream
      results[:has_xmp_stream] = true
      xmp_content = xmp_stream.stream.to_s
      results[:has_xmp_pdfua_identification] = xmp_content.include?("pdfuaid:part") && xmp_content.include?("pdfuaid:conformance")
      results[:has_xmp_dc_title] = xmp_content.include?("<dc:title>")

      # Extract conformance level
      results[:xmp_conformance_level] = Regexp.last_match(1).upcase if xmp_content =~ /pdfuaid:conformance="([a-z])"/
    end

    # Check structure tree depth
    if results[:has_struct_tree]
      struct_root = doc.catalog[:StructTreeRoot]
      results[:struct_tree_elements] = count_struct_elements(struct_root)
    end

    # Check if pages have marked content streams
    doc.pages.each do |page|
      results[:pages_with_marked_content] += 1 if page.contents&.to_s&.include?("BDC") # Begin Marked Content
    end

    # Overall accessibility assessment
    results[:is_truly_accessible] =
      results[:has_language] &&
      results[:has_mark_info] &&
      results[:has_struct_tree] &&
      results[:struct_tree_elements].positive? &&
      results[:pages_with_marked_content].positive? &&
      results[:has_title] &&
      results[:has_creator] &&
      results[:has_producer] &&
      results[:has_display_doc_title] &&
      results[:has_xmp_stream] &&
      results[:has_xmp_pdfua_identification] &&
      results[:has_xmp_dc_title]

    results
  end

  def self.count_struct_elements(struct_root, depth = 0)
    count = 1
    kids = struct_root[:K]

    if kids.is_a?(Array)
      kids.each { |kid| count += count_struct_elements(kid, depth + 1) if kid.is_a?(Hash) }
    elsif kids.is_a?(Hash)
      count += count_struct_elements(kids, depth + 1)
    end

    count
  end
end
