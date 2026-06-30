require "zip"
require "nokogiri"

# Fixes numbering corruption that occurs when LibreOffice converts DOCX to PDF.
#
# Root cause — HIDDEN COUNTER-SETTER PARAGRAPHS:
#   Word authors mark paragraphs <w:vanish/> in the paragraph-mark run
#   properties to "anchor" a multi-level list counter to a section number
#   without displaying any text.  For example, an invisible paragraph with
#   numId=3 at ilvl=0 before section 2 makes subsequent ilvl=1 items render
#   as "2.1.", "2.2.", etc. in Word.
#
#   LibreOffice renders these hidden paragraphs as visible numbered lines,
#   so the counter starts one position too early and the ghost number appears
#   on the page.  Fix: clone the numId with an explicit <w:startOverride>
#   set to the current heading count, then reassign the hidden paragraph and
#   all subsequent same-numId paragraphs to the clone.
#
# What we do NOT touch:
#   Paragraphs with <w:numId w:val="0"/> — these suppress a paragraph-style's
#   built-in numbering (e.g. "TABLE OF CONTENTS" Heading1).  LibreOffice
#   respects this signal, so leaving it alone is correct.  Removing it causes
#   the paragraph to inherit the style's numbering and shifts every subsequent
#   heading number up by one.
class DocxNumberingFixer
  W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

  CONTENT_ENTRIES = %w[
    word/document.xml
    word/header1.xml word/header2.xml word/header3.xml
    word/footer1.xml word/footer2.xml word/footer3.xml
  ].freeze

  def self.fix!(docx_path)
    new(docx_path).fix!
  end

  def initialize(docx_path)
    @docx_path = docx_path
  end

  def fix!
    tmp_path = "#{@docx_path}.numbering_fix.tmp"

    Zip::File.open(@docx_path) do |zip|
      num_xml = read_entry(zip, "word/numbering.xml")
      doc_xml = read_entry(zip, "word/document.xml")

      # If either required XML is missing just copy the archive unchanged
      unless num_xml && doc_xml
        Zip::OutputStream.open(tmp_path) { |out| copy_zip(zip, out) }
        FileUtils.mv(tmp_path, @docx_path)
        return @docx_path
      end

      num_doc  = Nokogiri::XML(num_xml) { |c| c.strict }
      body_doc = Nokogiri::XML(doc_xml) { |c| c.strict }

      new_num_nodes = patch_document!(body_doc, num_doc)

      Zip::OutputStream.open(tmp_path) do |out|
        zip.each do |entry|
          next if entry.directory?

          out.put_next_entry(
            entry.name, nil, nil,
            Zip::Entry::DEFLATED,
            Zlib::DEFAULT_COMPRESSION
          )

          case entry.name
          when "word/numbering.xml"
            out.write(build_numbering_xml(num_doc, new_num_nodes))
          when "word/document.xml"
            out.write(body_doc.to_xml(encoding: "UTF-8"))
          else
            out.write(entry.get_input_stream.read)
          end
        end
      end
    end

    FileUtils.mv(tmp_path, @docx_path)
    @docx_path
  ensure
    FileUtils.rm_f(tmp_path) if File.exist?(tmp_path.to_s)
  end

  private

  # Single-pass scan: for each hidden ilvl=0 list paragraph, clone its numId
  # with a startOverride equal to the current heading count, then redirect
  # that para and all following same-numId paras to the clone.
  # Returns an array of new <w:num> Nokogiri nodes to append to numbering.xml.
  def patch_document!(body_doc, num_doc)
    ns = { "w" => W_NS }

    # Build numId -> abstractNumId map from numbering.xml
    num_to_abstract = {}
    num_doc.xpath("//w:num", ns).each do |num|
      nid = wval(num, "numId")
      ab  = num.at_xpath("w:abstractNumId", ns)
      num_to_abstract[nid] = wval(ab, "val") if nid && ab
    end

    # Next available numId (above current max)
    max_num_id = num_to_abstract.keys.map(&:to_i).max || 100

    heading_num    = 0
    # original_numId -> currently active clone numId (changes as we scan)
    active_clone   = {}
    # (original_numId, heading_num) -> clone numId (avoid duplicate clones)
    clone_cache    = {}
    new_num_nodes  = []

    body_doc.xpath("//w:body/w:p", ns).each do |para|
      pPr = para.at_xpath("w:pPr", ns)
      next unless pPr

      style_el = pPr.at_xpath("w:pStyle", ns)
      style    = wval(style_el, "val")
      numPr    = pPr.at_xpath("w:numPr", ns)
      nid_el   = numPr&.at_xpath("w:numId", ns)
      ilvl_el  = numPr&.at_xpath("w:ilvl", ns)
      num_id   = nid_el ? wval(nid_el, "val") : nil
      ilvl     = ilvl_el ? wval(ilvl_el, "val").to_i : nil

      # Track non-suppressed Heading1 paragraphs for counter reference
      if style == "Heading1" && num_id != "0"
        heading_num += 1
      end

      # Only act on real list paragraphs (numId present and not 0)
      next unless num_id && num_id != "0" && !ilvl.nil?

      # Detect hidden paragraph-mark (vanish in pPr/w:rPr)
      p_rPr  = pPr.at_xpath("w:rPr", ns)
      vanish = p_rPr&.at_xpath("w:vanish", ns)

      if ilvl == 0 && vanish
        # Hidden ilvl=0 counter-setter: needs a clone with startOverride
        cache_key = "#{num_id}_#{heading_num}"

        unless clone_cache[cache_key]
          abstract_id = num_to_abstract[num_id]
          unless abstract_id
            next  # can't clone without an abstractNumId
          end

          max_num_id += 1
          new_id = max_num_id.to_s
          clone_cache[cache_key] = new_id
          num_to_abstract[new_id] = abstract_id

          new_node = build_num_node(num_doc, new_id, abstract_id, 0, heading_num)
          new_num_nodes << new_node

          Rails.logger.debug do
            "[DocxNumberingFixer] numId=#{num_id} h=#{heading_num} " \
              "-> clone numId=#{new_id} startOverride=#{heading_num}"
          end
        end

        clone_id = clone_cache[cache_key]
        active_clone[num_id] = clone_id
        # Patch this paragraph
        set_wval(nid_el, clone_id)

      elsif active_clone[num_id]
        # Visible paragraph using a numId that has been cloned — redirect it
        # Exception: another hidden ilvl=0 for the same numId re-anchors the
        # counter, so we skip re-patching hidden ilvl=0 paras here.
        set_wval(nid_el, active_clone[num_id])
      end
    end

    Rails.logger.debug { "[DocxNumberingFixer] Added #{new_num_nodes.size} numId clone(s)" }
    new_num_nodes
  end

  def build_numbering_xml(num_doc, new_num_nodes)
    return num_doc.to_xml(encoding: "UTF-8") if new_num_nodes.empty?

    new_num_nodes.each { |node| num_doc.root.add_child(node) }
    num_doc.to_xml(encoding: "UTF-8")
  end

  def build_num_node(num_doc, num_id, abstract_num_id, ilvl, start_val)
    Nokogiri::XML::Builder.with(num_doc.root) do |_|
      # We build a standalone fragment, not nested inside root
    end

    fragment = Nokogiri::XML::DocumentFragment.parse(
      <<~XML
        <w:num xmlns:w="#{W_NS}" w:numId="#{num_id}">
          <w:abstractNumId w:val="#{abstract_num_id}"/>
          <w:lvlOverride w:ilvl="#{ilvl}">
            <w:startOverride w:val="#{start_val}"/>
          </w:lvlOverride>
        </w:num>
      XML
    )
    fragment.first_element_child
  end

  def copy_zip(zip, out)
    zip.each do |entry|
      next if entry.directory?
      out.put_next_entry(
        entry.name, nil, nil,
        Zip::Entry::DEFLATED,
        Zlib::DEFAULT_COMPRESSION
      )
      out.write(entry.get_input_stream.read)
    end
  end

  def read_entry(zip, name)
    entry = zip.find_entry(name)
    entry&.get_input_stream&.read
  end

  def wval(el, attr = "val")
    return nil unless el
    el["#{W_NS}#{attr}"] || el["w:#{attr}"]
  end

  def set_wval(el, val)
    return unless el
    if el["#{W_NS}val"]
      el["#{W_NS}val"] = val
    else
      el["w:val"] = val
    end
  end
end
