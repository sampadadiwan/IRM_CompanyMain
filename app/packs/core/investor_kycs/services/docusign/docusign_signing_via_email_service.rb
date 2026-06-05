# frozen_string_literal: true

require 'pdf-reader'

class DocusignSigningViaEmailService
  include ApiCreator

  attr_reader :args, :doc

  def initialize(args, doc)
    @args = args
    @doc = doc
  end

  def worker
    # Create the envelope request object
    envelope_definition = make_envelope
    # Call Envelopes::create API method
    # Exceptions will be caught by the calling function
    envelope_api = create_envelope_api(args)

    results = envelope_api.create_envelope(args[:account_id], envelope_definition)
    # results = nil #envelope_api.create_envelope(args[:account_id], envelope_definition)

    envelope_id = results.envelope_id
    { 'envelope_id' => envelope_id }
  end

  private

  def make_envelope
    envelope_definition = DocuSign_eSign::EnvelopeDefinition.new

    envelope_definition.email_subject = "Please sign #{@doc.name} with #{@doc.entity.name}"

    tmpfile = @doc.file.download
    begin
      data = File.read(tmpfile.path)
    ensure
      tmpfile.close
      tmpfile.unlink
    end

    encoded_file = Base64.strict_encode64(data)
    # fetch from esign
    raise "Only PDF files are supported for eSigning" unless @doc.file.mime_type.include?("pdf")

    document = DocuSign_eSign::Document.new
    # (document_base64: encoded_file, name: @doc.name, file_extension:, document_id: @doc.id )
    document.document_base64 = encoded_file

    document.name = @doc.name.truncate(100)
    document.file_extension = 'pdf'
    document.document_id = @doc.id

    # The order in the docs array determines the order in the envelope
    envelope_definition.documents = [document]

    # Create the signer recipient model
    signers = prep_user_data(doc, doc.e_signatures)

    # Add the recipients to the envelope object
    recipients = DocuSign_eSign::Recipients.new
    recipients.signers = signers
    # Request that the envelope be sent by setting status to "sent".
    # To request that the envelope be created as a draft, set status to "created"
    envelope_definition.recipients = recipients
    envelope_definition.status = "sent"
    envelope_definition
  end

  # rubocop:disable Metrics/MethodLength
  def prep_user_data(doc, esigns)
    signers = []

    doc_last_page = 1
    page_height = 792  # default letter height
    page_width = 612   # default letter width

    # identify last page and get page dimensions
    doc.file.download do |tmpfile|
      reader = PDF::Reader.new(tmpfile.path)
      doc_last_page = reader.pages.count
      first_page = reader.pages.first
      page_height = first_page.height
      page_width = first_page.width
    end

    # Calculate maximum bounds with margins
    x_max = page_width - 80   # Keep 80px margin from right edge
    y_max = page_height - 50  # Keep 50px margin from top

    # Assuming xpos and ypos are the starting coordinates
    # pdf has x from 0 (left) to page_width (right), y from 0 (top) to page_height (bottom)
    xstart = 30 # Starting from the left
    ystart = page_height - 50 # Starting from the bottom with 50px margin

    # Define the number of signatures per row and the vertical step
    signatures_per_row = 3
    # more than total 42 signers will not be supported
    # rubocop:disable Metrics/BlockLength
    esigns.order(:position).each_with_index do |esign, idx|
      signer = DocuSign_eSign::Signer.new
      signer.email = esign.email
      signer.name = esign.email
      signer.recipient_id = idx + 1
      signer.routing_order = idx + 1

      # same routing order for all signers if force_esign_order is false i.e we dont want to enforce the order
      signer.routing_order = 1 unless doc.force_esign_order

      pages = if doc.display_on_page.casecmp?("last")
                [doc_last_page]
              elsif doc.display_on_page.casecmp?("first")
                [1]
              elsif doc.display_on_page.casecmp?("all")
                (1..doc_last_page).to_a
              else
                doc.display_on_page.split(",").map(&:to_i)
              end

      # Calculate the row and column
      row = idx / signatures_per_row
      col = idx % signatures_per_row

      # Adjust positions based on row and column
      # y decreases as we go down from bottom (row 0 at bottom, each row goes down)
      xpos = (xstart + (col * 190)).to_i
      ypos = (ystart - (row * 50)).to_i

      # Validate positions don't exceed bounds
      raise "Signature x position #{xpos} exceeds maximum x #{x_max}" if xpos.to_i > x_max
      raise "Signature y position #{ypos} exceeds maximum y #{y_max}" if ypos.to_i > y_max

      sign_tabs = []
      pages.each do |page|
        sign_here = DocuSign_eSign::SignHere.new
        sign_here.document_id = doc.id
        sign_here.page_number = page

        sign_here.x_position = xpos
        sign_here.y_position = ypos

        sign_tabs.push(sign_here)
      end
      # Add the tabs model (including the sign_here tabs) to the signer
      tabs = DocuSign_eSign::Tabs.new
      tabs.sign_here_tabs = sign_tabs
      signer.tabs = tabs

      signers.push(signer)
    end
    # rubocop:enable Metrics/BlockLength

    signers
  end
  # rubocop:enable Metrics/MethodLength
end
