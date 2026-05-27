class PdfAccessibilityCheckJob < ApplicationJob
  queue_as :default

  def perform(document_id, user_id)
    document = Document.find(document_id)
    results = PdfAccessibilityService.verify_pdf_accessibility(document.file.download.path, user_id)

    # msg = "This will send an email to the recipients who have access to this document using custom notification
    #               <br><strong>#{link_to cust_not.subject, custom_notification_path(cust_not), target: '_blank'}</strong><br>Proceed?<br>
    #               #{link_to 'View Who Gets Notified', show_email_list_document_path(@document), class: 'mb-1 badge bg-primary-subtle text-primary', target: '_blank'}"
    msg = "📋 PDF Accessibility Report for: #{document.name}"
    msg += "<br><strong>Structure & Compliance:</strong>"
    msg += "<br>- Language Setting: #{results[:has_language] ? '✅ Present' : '❌ Missing'}"
    msg += "<br>- MarkInfo: #{results[:has_mark_info] ? '✅ Present' : '❌ Missing'}"
    msg += "<br>- Structure Tree: #{results[:has_struct_tree] ? '✅ Present' : '❌ Missing'} (#{results[:struct_tree_elements]} elements)"
    msg += "<br>- Pages with Marked Content: #{results[:pages_with_marked_content]} / #{results[:total_pages]}"
    msg += "<br><br><strong>Document Metadata (Info Dictionary):</strong>"
    msg += "<br>- Title: #{results[:has_title] ? '✅ Present' : '❌ Missing'}"
    msg += "<br>- Author: #{results[:has_author] ? '✅ Present' : '❌ Missing'}"
    msg += "<br>- Subject: #{results[:has_subject] ? '✅ Present' : '❌ Missing'}"
    msg += "<br>- Keywords: #{results[:has_keywords] ? '✅ Present' : '❌ Missing'}"
    msg += "<br>- Creator: #{results[:has_creator] ? '✅ Present' : '❌ Missing'}"
    msg += "<br>- Producer: #{results[:has_producer] ? '✅ Present' : '❌ Missing'}"
    msg += "<br>- Creation Date: #{results[:has_creation_date] ? '✅ Present' : '❌ Missing'}"
    msg += "<br>- Modification Date: #{results[:has_mod_date] ? '✅ Present' : '❌ Missing'}"
    msg += "<br><br><strong>XMP Metadata Stream:</strong>"
    msg += "<br>- XMP Stream: #{results[:has_xmp_stream] ? '✅ Present' : '❌ Missing'}"
    msg += "<br>- PDF/UA Identification: #{results[:has_xmp_pdfua_identification] ? '✅ Present' : '❌ Missing'}"
    msg += " (Conformance: #{results[:xmp_conformance_level]})" if results[:xmp_conformance_level]
    msg += "<br>- DC Title Element: #{results[:has_xmp_dc_title] ? '✅ Present' : '❌ Missing'}"
    msg += "<br><br><strong>Document Settings:</strong>"
    msg += "<br>- Display Document Title: #{results[:has_display_doc_title] ? '✅ Enabled' : '❌ Disabled'}"
    msg += "<br><br>Overall Accessibility: #{results[:is_truly_accessible] ? '✅ Fully Compliant (PDF/UA-1)' : '⚠️ Not Fully Compliant'}"

    level = results[:is_truly_accessible] ? "success" : "warning"
    UserAlert.new(user_id:, message: msg, level:).broadcast
    Rails.logger.info "PDF Accessibility Check Results: #{results.inspect}"
  rescue StandardError => e
    msg = "Error during PDF accessibility check: #{e.message}"
    UserAlert.new(user_id:, message: msg, level: "error").broadcast
    Rails.logger.error { msg }
  end
end
