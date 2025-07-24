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
    data = File.read(tmpfile.path)

    encoded_file = Base64.strict_encode64(data)
    # fetch from esign
    raise "Only PDF files are supported for eSigning" unless @doc.file.mime_type.include?("pdf")

    document = DocuSign_eSign::Document.new
    # (document_base64: encoded_file, name: @doc.name, file_extension:, document_id: @doc.id )
    document.document_base64 = encoded_file

    document.name = @doc.name.truncate(100)
    document.file_extension = 'pdf'
    document.document_id = @doc.id

    tmpfile.close

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
    # identify last page
    doc.file.download do |tmpfile|
      reader = PDF::Reader.new(tmpfile.path)
      doc_last_page = reader.pages.count
    end

    # Assuming xpos and ypos are the starting coordinates
    # pdf hass x from 0 to 620
    xstart = 30 # Starting from the left
    ystart = 750 # Starting from the bottom (assuming the bottom y-coordinate is 0 and top is 800)

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
      xpos = (xstart + (col * 190)).to_s
      ypos = (ystart - (row * 50)).to_s
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
