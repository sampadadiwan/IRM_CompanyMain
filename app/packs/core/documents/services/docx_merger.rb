require "zip"
require "nokogiri"
require "fileutils"

# Merges multiple .docx files into one, in order, inserting a page break between each.
#
# This is scoped to the case that actually shows up in practice today: every input file was
# generated from the SAME source template (e.g. the same PortfolioReportTemplate, mail-merged
# with different data per company) — so styles.xml/theme/fontTable and the template's own
# numbering/relationship definitions are identical across files. Only the things each generator
# run adds ON TOP of that shared base can differ between files and need remapping when
# concatenated:
#   - DocxNumberingFixer (see docx_numbering_fixer.rb) injects file-local cloned <w:num> entries
#     with fresh numeric ids AFTER generation — these ids are only unique within one file.
#   - A per-company embedded image (e.g. PortfolioReportDocGenerator's logo merge field) means
#     word/media/*, word/_rels/document.xml.rels and [Content_Types].xml can genuinely differ.
#
# Files from DIFFERENT templates can be joined too (a cover page and the per-company reports, say):
# the first file's styles, page setup and running header/footer win for the whole document, and
# later files contribute their content only. Only the relationships a later file's content actually
# uses (images, hyperlinks) are brought across; its styles, theme, settings, header and footer
# relationships are left behind so no relationship ever points at a part that was not copied.
#
# What this does NOT attempt: independent sections with their own header/footer per merged file
# (everything lands in one continuous section using the base file's sectPr/header/footer), or
# reconciling differing base styles/numbering definitions between files: a later file's styles that
# the first file does not define fall back to the default style.
class DocxMerger
  W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main".freeze
  R_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships".freeze
  RELS_NS = "http://schemas.openxmlformats.org/package/2006/relationships".freeze
  CT_NS = "http://schemas.openxmlformats.org/package/2006/content-types".freeze
  NS = { "w" => W_NS, "r" => R_NS }.freeze

  IMAGE_CONTENT_TYPES = {
    "png" => "image/png", "jpg" => "image/jpeg", "jpeg" => "image/jpeg", "gif" => "image/gif"
  }.freeze

  def self.merge(paths, output_path)
    new(paths, output_path).merge
  end

  def initialize(paths, output_path)
    @paths = paths.to_a
    @output_path = output_path
  end

  def merge
    return FileUtils.cp(@paths.first, @output_path) if @paths.size <= 1

    extra_entries = {}

    Zip::File.open(@paths.first) do |base_zip|
      doc_xml = read_xml(base_zip, "word/document.xml")
      raise "word/document.xml missing from #{@paths.first}" unless doc_xml

      num_xml  = read_xml(base_zip, "word/numbering.xml")
      rels_xml = read_xml(base_zip, "word/_rels/document.xml.rels")
      ct_xml   = read_xml(base_zip, "[Content_Types].xml")

      body = doc_xml.at_xpath("//w:body", NS)
      sect_pr = body.at_xpath("w:sectPr", NS)

      base_num_ids = num_xml ? existing_num_ids(num_xml) : []
      next_num_id = base_num_ids.map(&:to_i).max.to_i + 1
      next_rid = rels_xml ? (max_rid(rels_xml) + 1) : 1

      @paths[1..].each_with_index do |path, file_idx|
        Zip::File.open(path) do |zip|
          other_doc = read_xml(zip, "word/document.xml")
          next unless other_doc

          other_rels = read_xml(zip, "word/_rels/document.xml.rels")
          other_num  = read_xml(zip, "word/numbering.xml")
          other_body = other_doc.at_xpath("//w:body", NS)
          other_sect_pr = other_body&.at_xpath("w:sectPr", NS)

          rid_map = {}
          if other_rels && rels_xml
            used_rids = content_rids(other_body, other_sect_pr)
            other_rels.xpath("//rel:Relationship", "rel" => RELS_NS).each do |rel|
              # X9 sibling: skip relationships the copied content never refers to (styles, theme, header, footer ...)
              next unless used_rids.include?(rel["Id"])

              new_id = "rId#{next_rid}"
              next_rid += 1
              rid_map[rel["Id"]] = new_id

              new_target = rel["Target"].to_s
              if new_target.start_with?("media/")
                media_name = File.basename(new_target)
                new_media_name = "merged#{file_idx}_#{media_name}"
                new_target = "media/#{new_media_name}"

                media_bytes = zip.find_entry("word/media/#{media_name}")&.get_input_stream&.read
                extra_entries["word/#{new_target}"] = media_bytes if media_bytes

                ensure_content_type(ct_xml, File.extname(new_media_name).delete(".").downcase) if ct_xml
              end

              add_relationship(rels_xml, new_id, rel["Type"], new_target, rel["TargetMode"])
            end
          end

          remap_r_ids!(other_doc, rid_map)
          next_num_id = remap_numbering!(other_doc, other_num, num_xml, base_num_ids, next_num_id)

          next unless sect_pr && other_body

          children = other_body.children.reject { |child| child == other_sect_pr }
          children = children.map { |child| child.dup(1) }
          sect_pr.add_previous_sibling(page_break_fragment) unless break_before_first_paragraph!(children)
          children.each { |child| sect_pr.add_previous_sibling(child) }
        end
      end

      write_output(base_zip, doc_xml, num_xml, rels_xml, ct_xml, extra_entries)
    end

    @output_path
  end

  private

  def write_output(base_zip, doc_xml, num_xml, rels_xml, ct_xml, extra_entries)
    Zip::OutputStream.open(@output_path) do |out|
      base_zip.each do |entry|
        next if entry.directory?

        out.put_next_entry(entry.name, nil, nil, Zip::Entry::DEFLATED, Zlib::DEFAULT_COMPRESSION)
        out.write(patched_content(entry, doc_xml, num_xml, rels_xml, ct_xml))
      end

      extra_entries.each do |name, bytes|
        next if base_zip.find_entry(name)

        out.put_next_entry(name, nil, nil, Zip::Entry::DEFLATED, Zlib::DEFAULT_COMPRESSION)
        out.write(bytes)
      end
    end
  end

  def patched_content(entry, doc_xml, num_xml, rels_xml, ct_xml)
    case entry.name
    when "word/document.xml"
      doc_xml.to_xml(encoding: "UTF-8")
    when "word/numbering.xml"
      num_xml&.to_xml(encoding: "UTF-8") || entry.get_input_stream.read
    when "word/_rels/document.xml.rels"
      rels_xml&.to_xml(encoding: "UTF-8") || entry.get_input_stream.read
    when "[Content_Types].xml"
      ct_xml&.to_xml(encoding: "UTF-8") || entry.get_input_stream.read
    else
      entry.get_input_stream.read
    end
  end

  def read_xml(zip, name)
    entry = zip.find_entry(name)
    return nil unless entry

    Nokogiri::XML(entry.get_input_stream.read, &:strict)
  end

  def existing_num_ids(num_xml)
    num_xml.xpath("//w:num", NS).filter_map { |n| n["w:numId"] }
  end

  def max_rid(rels_xml)
    ids = rels_xml.xpath("//rel:Relationship", "rel" => RELS_NS).filter_map { |r| r["Id"].to_s[/\d+/] }.map(&:to_i)
    ids.max || 0
  end

  # Rewrites this file's r:id/r:embed references (hyperlinks, images) to the freshly
  # assigned relationship ids so they don't collide with (or point at the wrong entry in)
  # the base file's own relationships.
  def remap_r_ids!(doc, rid_map)
    return if rid_map.empty?

    # Every attribute in the relationships namespace (r:id, r:embed, r:link ...) names a relationship
    doc.xpath("//@*[namespace-uri()='#{R_NS}']").each do |attr|
      new_id = rid_map[attr.value]
      attr.value = new_id if new_id
    end
  end

  # The relationship ids used by the content that is copied (everything in the body except its sectPr).
  def content_rids(body, sect_pr)
    return [] unless body

    body.children.reject { |child| child == sect_pr }.flat_map do |child|
      child.xpath(".//@*[namespace-uri()='#{R_NS}']").map(&:value)
    end.uniq
  end

  # Only numIds that are NOT already part of the base file's numbering.xml need remapping —
  # those are DocxNumberingFixer-injected clones local to this one file. Returns the updated
  # next_num_id counter.
  def remap_numbering!(other_doc, other_num, base_num_xml, base_num_ids, next_num_id)
    return next_num_id unless other_num

    num_id_map = {}
    other_num.xpath("//w:num", NS).each do |num_node|
      old_id = num_node["w:numId"]
      next unless old_id
      next if base_num_ids.include?(old_id)

      new_id = next_num_id.to_s
      next_num_id += 1
      num_id_map[old_id] = new_id

      next unless base_num_xml

      clone = num_node.dup(1)
      clone["w:numId"] = new_id
      base_num_xml.root.add_child(clone)
    end

    unless num_id_map.empty?
      other_doc.xpath("//w:numId", NS).each do |node|
        new_val = num_id_map[node["w:val"]]
        node["w:val"] = new_val if new_val
      end
    end

    next_num_id
  end

  # A page break of its own sits on a new page when the previous file fills its page to the bottom,
  # and then breaks again, leaving a blank page. Starting the next file's first paragraph on a new
  # page adds no paragraph that can spill over. Returns false when the file does not start with a
  # paragraph (a table, say), so the caller falls back to the separate break.
  def break_before_first_paragraph!(children)
    first = children.find(&:element?)
    return false unless first&.name == "p" && first.namespace&.href == W_NS

    p_pr = first.at_xpath("w:pPr", NS) || first.prepend_child(new_w_node(first, "pPr"))
    return true if p_pr.at_xpath("w:pageBreakBefore", NS)

    node = new_w_node(first, "pageBreakBefore")
    # CT_PPr order: pStyle, keepNext and keepLines come before pageBreakBefore
    preceding = p_pr.xpath("w:pStyle|w:keepNext|w:keepLines", NS).last
    preceding ? preceding.add_next_sibling(node) : p_pr.prepend_child(node)
    true
  end

  def new_w_node(sibling, name)
    Nokogiri::XML::Node.new(name, sibling.document).tap { |node| node.namespace = sibling.namespace }
  end

  def page_break_fragment
    Nokogiri::XML::DocumentFragment.parse(
      %(<w:p xmlns:w="#{W_NS}"><w:r><w:br w:type="page"/></w:r></w:p>)
    ).first_element_child
  end

  def ensure_content_type(ct_xml, ext)
    return if ext.blank?
    return if ct_xml.xpath("//ct:Default[@Extension='#{ext}']", "ct" => CT_NS).any?

    content_type = IMAGE_CONTENT_TYPES[ext] || "application/octet-stream"
    frag = Nokogiri::XML::DocumentFragment.parse(
      %(<Default xmlns="#{CT_NS}" Extension="#{ext}" ContentType="#{content_type}"/>)
    )
    ct_xml.root.add_child(frag.first_element_child)
  end

  def add_relationship(rels_xml, id, type, target, target_mode)
    attrs = %(Id="#{escape(id)}" Type="#{escape(type)}" Target="#{escape(target)}")
    attrs += %( TargetMode="#{escape(target_mode)}") if target_mode
    frag = Nokogiri::XML::DocumentFragment.parse(%(<Relationship xmlns="#{RELS_NS}" #{attrs}/>))
    rels_xml.root.add_child(frag.first_element_child)
  end

  def escape(value)
    value.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
  end
end
