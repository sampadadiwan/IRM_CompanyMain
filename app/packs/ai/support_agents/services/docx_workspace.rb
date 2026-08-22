# frozen_string_literal: true

require "zip"
require "nokogiri"
require "open3"

# Holds the extracted, mutable state of a .docx template for the duration of a
# TemplateFixAgent run. Every editing tool (SearchDocxTextTool, EditParagraphTool,
# SetStylePropertyTool, ...) shares one instance so edits accumulate across the
# ReAct loop's tool calls before a final rezip — mirroring the data_manager
# pattern other RubyLLM::Tool classes are constructed with.
#
# XML parts are parsed once and mutated in place with Nokogiri (never
# re-parsed from a stale string mid-run), then serialized back only when a
# preview render or the final output is requested. This is the same
# Zip::File + Nokogiri(strict) + Zip::OutputStream idiom used by
# DocxNumberingFixer/DocxFormattingPreserver, so RunKnownFixerTool can shell
# out to those existing fixers and fold their output back in.
#
# @see TemplateFixAgent
class DocxWorkspace
  W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

  # Parts a tool is allowed to read/mutate. Deliberately excludes media,
  # relationships, and [Content_Types].xml — a bad edit there breaks the zip
  # in ways a well-formedness check on document.xml alone wouldn't catch.
  EDITABLE_PARTS = %w[
    word/document.xml word/styles.xml word/numbering.xml
    word/header1.xml word/header2.xml word/header3.xml
    word/footer1.xml word/footer2.xml word/footer3.xml
  ].freeze

  class InvalidPart < StandardError; end

  # Sablon's actual FieldHandlers (sablon/processor/document/field_handlers.rb):
  # InsertionHandler (^=), ConditionalHandler (:if/:elsif|:elseIf/:else/:endIf),
  # EachLoopHandler (:each(item)/:endEach). Notably there is NO ':unless' —
  # an LLM asked to hide a block when a condition is false will readily invent
  # one (confirmed live: it produced 'expr:unless'/'expr:endUnless', which no
  # handler claims, so Sablon leaves the field's cached display text — the
  # literal "«...»" — sitting untouched in the generated document, and the
  # "hidden" block still renders unconditionally). Reject anything that isn't
  # a real Sablon operation up front instead of only catching it at render time.
  VALID_SABLON_TAIL = /:(if|elsif|elseIf|else|endIf|each\([^)]+\)|endEach)\z/

  attr_reader :dir, :change_log, :initial_paragraph_counts, :content_check

  def initialize(document)
    @document = document
    @dir = Dir.mktmpdir("template_fix_")
    @source_docx_path = File.join(@dir, "source.docx")
    document.file.download { |tempfile| FileUtils.cp(tempfile.path, @source_docx_path) }
    @parsed = {} # part_name => Nokogiri::XML::Document, mutated in place
    @change_log = []
    @initial_paragraph_counts = {}
    @initial_paragraph_words = {} # part_name => [[word, word, ...], ...] one array per paragraph
    EDITABLE_PARTS.each do |pname|
      xml = read_raw_entry(@source_docx_path, pname)
      next unless xml

      doc = Nokogiri::XML(xml, &:strict)
      paras = doc.xpath("//w:p", "w" => W_NS)
      @initial_paragraph_counts[pname] = paras.size
      @initial_paragraph_words[pname] = paras.map { |p| words_in(paragraph_text(p)) }
    end
  end

  # Hard content-preservation gate. TemplateFixAgent fixes template STRUCTURE
  # only (numbering, indentation, pagination/style properties) — it has no
  # tool that creates a Sablon merge field, inserts a paragraph, or otherwise
  # has any legitimate reason to change what the template says. None of its
  # remaining tools ever touch a <w:t> element. So paragraph count, word
  # count, and the words themselves (whitespace/formatting differences aside)
  # must come out EXACTLY as they went in — no exceptions, no "insertions are
  # fine" carve-out (that carve-out existed only for the now-removed
  # DocxInsertMergeFieldTool). Raises at the FIRST point of divergence found,
  # not a generic pass/fail, so a human can see exactly what changed without
  # re-running a diff by hand.
  def validate_content_unchanged!
    orig_para_total = 0
    current_para_total = 0
    orig_word_total = 0
    current_word_total = 0
    word_for_word_ok = true
    first_failure = nil

    EDITABLE_PARTS.each do |pname|
      orig_count = @initial_paragraph_counts[pname]
      next unless orig_count

      orig_words = @initial_paragraph_words[pname]
      current_paras = paragraphs(pname)
      current_words = current_paras.map { |p| words_in(paragraph_text(p)) }
      orig_total = orig_words.sum(&:size)
      current_total = current_words.sum(&:size)

      orig_para_total += orig_count
      current_para_total += current_paras.size
      orig_word_total += orig_total
      current_word_total += current_total

      para_ok = current_paras.size == orig_count
      word_count_ok = orig_total == current_total
      first_diff_idx = para_ok ? orig_words.each_index.find { |idx| orig_words[idx] != current_words[idx] } : nil
      word_by_word_ok = para_ok && first_diff_idx.nil?
      word_for_word_ok &&= word_by_word_ok

      Rails.logger.info do
        "[DocxWorkspace] Content check #{pname}: paragraphs #{orig_count}/#{current_paras.size} " \
          "(#{para_ok ? 'PASS' : 'FAIL'}), words #{orig_total}/#{current_total} " \
          "(#{word_count_ok ? 'PASS' : 'FAIL'}), word-for-word #{word_by_word_ok ? 'PASS' : 'FAIL'}"
      end

      next if first_failure

      unless para_ok
        first_failure = "Content check failed for #{pname}: paragraph count changed from #{orig_count} to " \
                         "#{current_paras.size}. This agent must never add or remove paragraphs."
      end

      if !first_failure && !word_count_ok
        first_failure = "Content check failed for #{pname}: word count changed from #{orig_total} to " \
                         "#{current_total}. This agent must never add, remove, or reword content — only " \
                         "formatting/numbering/pagination structure."
      end

      if !first_failure && first_diff_idx
        idx = first_diff_idx
        first_failure = "Content check failed for #{pname} paragraph #{idx}: words changed.\n" \
                         "  before: #{orig_words[idx].join(' ').inspect}\n" \
                         "  after:  #{current_words[idx].join(' ').inspect}"
      end
    end

    # Stored regardless of pass/fail so the UI/report can show the actual
    # numbers either way — TemplateFixAgent#finalize_fix reads this even when
    # the raise below sends it into the rescue path.
    @content_check = {
      paragraph_count: { original: orig_para_total, fixed: current_para_total },
      word_count: { original: orig_word_total, fixed: current_word_total },
      word_for_word_match: word_for_word_ok && first_failure.nil?,
      passed: first_failure.nil?
    }

    if first_failure
      Rails.logger.error { "[DocxWorkspace] #{first_failure}" }
      raise first_failure
    end

    true
  end

  # Returns the parsed, mutable Nokogiri document for a part, loading it from
  # the current baseline docx on first access. Subsequent calls (including
  # from other tools) return the SAME in-memory tree so edits accumulate.
  def part(part_name)
    validate_part!(part_name)

    return @parsed[part_name] if @parsed.key?(part_name)

    xml = read_raw_entry(@source_docx_path, part_name)
    return nil if xml.nil?

    @parsed[part_name] = Nokogiri::XML(xml, &:strict)
  end

  # All <w:p> paragraphs in a part, in document order. Index into this array
  # (0-based) is the stable "paragraph index" tools use to refer to a specific
  # paragraph across calls — stable because paragraphs are never reordered by
  # any tool, only mutated or inserted adjacent to an existing one.
  def paragraphs(part_name)
    doc = part(part_name)
    return [] unless doc

    doc.xpath("//w:p", "w" => W_NS)
  end

  def paragraph_at(part_name, index)
    paragraphs(part_name)[index.to_i]
  end

  def paragraph_text(node)
    return "" unless node

    node.xpath(".//w:t", "w" => W_NS).map(&:text).join
  end

  # Whitespace-normalized word list for a paragraph's text — used by
  # validate_content_unchanged! so a pure formatting edit (which never
  # changes wording, only how it's indented/spaced/tabbed) can't trip the
  # check on an incidental whitespace difference.
  def words_in(text)
    text.to_s.tr(" ", " ").split(/\s+/).reject(&:empty?)
  end

  # OOXML parts always serialize the "w" namespace with that literal prefix,
  # so a plain "w:attr" lookup matches Nokogiri's attribute name directly —
  # confirmed against real document.xml content, no namespace-aware [] needed.
  def wval(el, attr = "val")
    el&.[]("w:#{attr}")
  end

  def set_wval(el, val, attr = "val")
    return unless el

    el["w:#{attr}"] = val
  end

  def record_change(description)
    @change_log << description
  end

  # Substring search over each paragraph's joined text (spans runs Word split
  # mid-word, the way a naive per-run search would miss). Returns at most
  # `limit` matches so a hit in a huge document.xml doesn't flood the LLM's
  # context — callers needing more should narrow the query.
  #
  # word/styles.xml has no <w:p> body paragraphs at all (style definitions are
  # <w:style> elements with a styleId attribute and a <w:name> child, not
  # paragraph text) — searching it as paragraph text always finds nothing, so
  # that part is routed to a style-aware search instead.
  def find_matches(part_name, query, limit: 20)
    return find_style_matches(query, limit: limit) if part_name == "word/styles.xml"

    paragraphs(part_name).each_with_index.filter_map do |p, idx|
      text = paragraph_text(p)
      next unless text.include?(query)

      { index: idx, text: text }
    end.first(limit)
  end

  # Substring search over styles.xml's <w:style> definitions, matched against
  # styleId and display name — e.g. finding "Heading4" (the styleId reported by
  # inspect_paragraph's `style:` field) or "heading 4" (its display name).
  def find_style_matches(query, limit: 20)
    doc = part("word/styles.xml")
    return [] unless doc

    doc.xpath("//w:style", "w" => W_NS).filter_map do |style|
      style_id = style["w:styleId"]
      name = wval(style.at_xpath("w:name", "w" => W_NS))
      haystack = [style_id, name].compact.join(" ")
      next unless haystack.downcase.include?(query.to_s.downcase)

      pPr = style.at_xpath("w:pPr", "w" => W_NS)
      { style_id: style_id, name: name, ppr_xml: pPr&.to_xml }
    end.first(limit)
  end

  # Diagnostic dump of one paragraph: text, style, numbering, and the raw pPr
  # block — mirrors exactly what was inspected by hand to find the Individual.docx
  # bug (style/numPr mismatches that a text-only view can't reveal).
  def inspect_paragraph(part_name, index)
    p = paragraph_at(part_name, index)
    return nil unless p

    pPr = p.at_xpath("w:pPr", "w" => W_NS)
    numPr = pPr&.at_xpath("w:numPr", "w" => W_NS)

    {
      index: index,
      text: paragraph_text(p),
      style: wval(pPr&.at_xpath("w:pStyle", "w" => W_NS)),
      ilvl: wval(numPr&.at_xpath("w:ilvl", "w" => W_NS)),
      numId: wval(numPr&.at_xpath("w:numId", "w" => W_NS)),
      ppr_xml: pPr&.to_xml
    }
  end

  # numId -> abstractNumId map plus any per-instance lvlOverride/startOverride
  # values from numbering.xml — the piece that explained why two independently
  # restarting lists (numId 2 vs 251) could both legitimately display "5.2.9".
  def list_numbering(num_id: nil)
    doc = part("word/numbering.xml")
    return [] unless doc

    doc.xpath("//w:num", "w" => W_NS).filter_map do |num|
      nid = wval(num, "numId")
      next if num_id.present? && nid != num_id.to_s

      abstract_id = wval(num.at_xpath("w:abstractNumId", "w" => W_NS))
      overrides = num.xpath("w:lvlOverride", "w" => W_NS).map do |lvl_override|
        {
          ilvl: wval(lvl_override, "ilvl"),
          start_override: wval(lvl_override.at_xpath("w:startOverride", "w" => W_NS))
        }
      end
      { num_id: nid, abstract_num_id: abstract_id, lvl_overrides: overrides }
    end
  end

  # Adds/overwrites the numPr (ilvl + numId) on an existing paragraph, creating
  # pPr/numPr if either is missing. Used both for correcting a wrong numId and
  # for adding an explicit override where a paragraph was silently inheriting
  # numbering from its style default (the Heading4 sub-item bug).
  def set_paragraph_numbering!(part_name, index, ilvl:, num_id:)
    p = paragraph_at(part_name, index)
    raise ArgumentError, "No paragraph at index #{index} in #{part_name}" unless p

    pPr = p.at_xpath("w:pPr", "w" => W_NS)
    if pPr.nil?
      pPr = Nokogiri::XML::Node.new("w:pPr", p.document)
      p.prepend_child(pPr)
    end

    numPr = pPr.at_xpath("w:numPr", "w" => W_NS)
    if numPr.nil?
      numPr = Nokogiri::XML::Node.new("w:numPr", p.document)
      pStyle = pPr.at_xpath("w:pStyle", "w" => W_NS)
      pStyle ? pStyle.add_next_sibling(numPr) : pPr.prepend_child(numPr)
    end

    ilvl_el = numPr.at_xpath("w:ilvl", "w" => W_NS) || numPr.add_child(Nokogiri::XML::Node.new("w:ilvl", p.document)).first
    numId_el = numPr.at_xpath("w:numId", "w" => W_NS) || numPr.add_child(Nokogiri::XML::Node.new("w:numId", p.document)).first

    set_wval(ilvl_el, ilvl.to_s)
    set_wval(numId_el, num_id.to_s)
  end

  # Replaces a paragraph's visible text with a single run, preserving the
  # paragraph's pPr untouched and carrying over the first existing run's rPr
  # (font/size/formatting) so the replacement doesn't silently lose styling —
  # the same approach the docx gem's Paragraph#text= uses.
  def replace_paragraph_text!(part_name, index, text)
    p = paragraph_at(part_name, index)
    raise ArgumentError, "No paragraph at index #{index} in #{part_name}" unless p

    first_run_rpr = p.at_xpath("w:r/w:rPr", "w" => W_NS)

    p.xpath("w:r | w:hyperlink | w:proofErr | w:bookmarkStart | w:bookmarkEnd | w:ins | w:del", "w" => W_NS).each(&:remove)

    new_r = Nokogiri::XML::Node.new("w:r", p.document)
    new_r.add_child(first_run_rpr.dup) if first_run_rpr
    t = Nokogiri::XML::Node.new("w:t", p.document)
    t["xml:space"] = "preserve"
    t.content = text
    new_r.add_child(t)
    p.add_child(new_r)
  end

  # Inserts a new paragraph immediately before/after an existing one, containing
  # a real Word complex merge field (begin/instrText/separate/display/end) —
  # not literal "«...»" text, which Sablon's mail-merge parser does not
  # recognize as a field at all (confirmed the hard way: a literal-text
  # conditional silently renders as inert text and both branches still show).
  #
  # @param position ["before", "after"]
  # @param clone_ppr_from [Integer, nil] paragraph index to copy pPr from
  #   (numPr stripped so the tag paragraph itself doesn't get numbered);
  #   defaults to the anchor paragraph's own pPr.
  def insert_merge_field_paragraph!(part_name, anchor_index, position:, expression:, display_text:, clone_ppr_from: nil)
    anchor = paragraph_at(part_name, anchor_index)
    raise ArgumentError, "No paragraph at index #{anchor_index} in #{part_name}" unless anchor
    raise ArgumentError, "position must be 'before' or 'after'" unless %w[before after].include?(position.to_s)
    # Sablon's field-expression regex is `[^ ]+` — a space silently truncates the
    # expression Sablon actually parses, producing a field that looks right in
    # Word but never matches the intended :if/:endIf pair.
    raise ArgumentError, "expression must not contain spaces: #{expression.inspect}" if expression.to_s.include?(" ")

    validate_sablon_expression!(expression)

    doc = anchor.document
    new_p = Nokogiri::XML::Node.new("w:p", doc)

    ppr_source_p = clone_ppr_from.present? ? paragraph_at(part_name, clone_ppr_from) : anchor
    ppr_source = ppr_source_p&.at_xpath("w:pPr", "w" => W_NS)
    if ppr_source
      cloned = ppr_source.dup
      cloned.xpath("w:numPr", "w" => W_NS).each(&:remove)
      new_p.add_child(cloned)
    end

    merge_field_runs(doc, expression, display_text).each { |r| new_p.add_child(r) }

    position.to_s == "before" ? anchor.add_previous_sibling(new_p) : anchor.add_next_sibling(new_p)
    new_p
  end

  # Sets indentation (left, hanging, firstLine) on a paragraph's pPr/w:ind.
  def set_paragraph_indentation!(part_name, index, left: nil, hanging: nil, first_line: nil)
    p = paragraph_at(part_name, index)
    raise ArgumentError, "No paragraph at index #{index} in #{part_name}" unless p

    pPr = p.at_xpath("w:pPr", "w" => W_NS)
    if pPr.nil?
      pPr = Nokogiri::XML::Node.new("w:pPr", p.document)
      p.prepend_child(pPr)
    end

    ind = pPr.at_xpath("w:ind", "w" => W_NS)
    if ind.nil?
      ind = Nokogiri::XML::Node.new("w:ind", p.document)
      pPr.add_child(ind)
    end

    set_wval(ind, left.to_s) if left.present?
    set_wval(ind, hanging.to_s, "hanging") if hanging.present?
    set_wval(ind, first_line.to_s, "firstLine") if first_line.present?
    ind
  end

  # Sets start counter or indentation on a specific abstractNum level in word/numbering.xml.
  def set_numbering_level!(abstract_num_id, ilvl, start: nil, left: nil, hanging: nil)
    doc = part("word/numbering.xml")
    raise ArgumentError, "word/numbering.xml not found" unless doc

    abn = doc.xpath("//w:abstractNum", "w" => W_NS).find { |a| a["w:abstractNumId"] == abstract_num_id.to_s }
    raise ArgumentError, "AbstractNum '#{abstract_num_id}' not found" unless abn

    lvl = abn.xpath("w:lvl", "w" => W_NS).find { |l| l["w:ilvl"] == ilvl.to_s }
    raise ArgumentError, "Level '#{ilvl}' not found in AbstractNum '#{abstract_num_id}'" unless lvl

    if start.present?
      start_el = lvl.at_xpath("w:start", "w" => W_NS)
      if start_el
        set_wval(start_el, start.to_s)
      else
        start_node = Nokogiri::XML::Node.new("w:start", doc)
        set_wval(start_node, start.to_s)
        lvl.prepend_child(start_node)
      end
    end

    if left.present? || hanging.present?
      pPr = lvl.at_xpath("w:pPr", "w" => W_NS)
      if pPr.nil?
        pPr = Nokogiri::XML::Node.new("w:pPr", doc)
        lvl.add_child(pPr)
      end
      ind = pPr.at_xpath("w:ind", "w" => W_NS)
      if ind.nil?
        ind = Nokogiri::XML::Node.new("w:ind", doc)
        pPr.add_child(ind)
      end
      set_wval(ind, left.to_s) if left.present?
      set_wval(ind, hanging.to_s, "hanging") if hanging.present?
    end
  end

  # Toggles a boolean paragraph-property flag (e.g. <w:keepNext/>) on a named
  # style in styles.xml — the fix for the Heading4-style-driven blank-page
  # pagination bug. Matches on the literal styleId attribute rather than an
  # interpolated XPath predicate to avoid any XPath-injection surface from an
  # LLM-supplied style_id.
  def set_style_property!(style_id:, property:, enabled:)
    # property becomes both an XPath fragment and an XML element local name below;
    # constrain it to a safe OOXML-identifier shape first (LLM-supplied, not trusted).
    raise ArgumentError, "Invalid property name: #{property.inspect}" unless property.to_s.match?(/\A[A-Za-z][A-Za-z0-9]*\z/)

    doc = part("word/styles.xml")
    raise ArgumentError, "word/styles.xml not found" unless doc

    style = doc.xpath("//w:style", "w" => W_NS).find { |s| s["w:styleId"] == style_id }
    raise ArgumentError, "Style '#{style_id}' not found" unless style

    pPr = style.at_xpath("w:pPr", "w" => W_NS)
    if pPr.nil?
      return unless enabled

      pPr = Nokogiri::XML::Node.new("w:pPr", style.document)
      rPr = style.at_xpath("w:rPr", "w" => W_NS)
      rPr ? rPr.add_previous_sibling(pPr) : style.add_child(pPr)
    end

    existing = pPr.at_xpath("w:#{property}", "w" => W_NS)
    if enabled
      pPr.prepend_child(Nokogiri::XML::Node.new("w:#{property}", style.document)) unless existing
    else
      existing&.remove
    end
  end

  # Re-zips the current in-memory state (baseline + all part edits) to a new
  # docx at output_path, preserving every other zip entry byte-for-byte and
  # in its original order.
  def rezip_to(output_path)
    Zip::File.open(@source_docx_path) do |zip|
      Zip::OutputStream.open(output_path) do |out|
        zip.each do |entry|
          next if entry.directory?

          out.put_next_entry(entry.name, nil, nil, Zip::Entry::DEFLATED, Zlib::DEFAULT_COMPRESSION)
          if @parsed.key?(entry.name)
            out.write(@parsed[entry.name].to_xml(encoding: "UTF-8"))
          else
            out.write(entry.get_input_stream.read)
          end
        end
      end
    end
    output_path
  end

  # Bakes the current state into a new baseline docx file, then hands that
  # path to a block (e.g. DocxNumberingFixer.fix!) that mutates it in place.
  # Clears the in-memory part cache afterward so the next `part`/`paragraphs`
  # call re-reads the fixer's output — folding its changes into the workspace
  # without losing any edits already made this run.
  def apply_external_fixer!
    baked_path = File.join(@dir, "baked_#{SecureRandom.hex(4)}.docx")
    rezip_to(baked_path)
    yield(baked_path)
    @source_docx_path = baked_path
    @parsed = {}
    true
  end

  # Re-zips the current state and converts it to PDF via headless LibreOffice
  # (the same conversion path used elsewhere in this app for docx previews),
  # returning extracted page text so the agent can "observe" its edits without
  # needing a vision-capable model.
  #
  # @return [Hash] { success:, page_count:, text:, blank_page_hints:, error: }
  def render_preview!
    candidate_path = File.join(@dir, "preview_#{SecureRandom.hex(4)}.docx")
    rezip_to(candidate_path)

    _out, err, status = Open3.capture3(
      "libreoffice", "--headless", "--convert-to", "pdf", "--outdir", @dir, candidate_path
    )
    pdf_path = candidate_path.sub(/\.docx\z/, ".pdf")
    return { success: false, error: err.presence || "LibreOffice conversion failed" } unless status.success? && File.exist?(pdf_path)

    text, _err, _status = Open3.capture3("pdftotext", "-layout", pdf_path, "-")
    page_count = text.count("\f") + (text.present? ? 1 : 0)

    { success: true, page_count: page_count, text: text, blank_page_hints: detect_blank_pages(text) }
  ensure
    File.delete(candidate_path) if candidate_path && File.exist?(candidate_path)
    File.delete(pdf_path) if pdf_path && File.exist?(pdf_path)
  end

  # Finalizes the workspace as a new Document attached to the same owner/folder
  # as the source template, named to make clear it's an AI-produced draft
  # awaiting human review — the source template itself is never modified.
  #
  # @return [Document] the newly created draft document
  def save_as_new_document!(name_suffix: "(AI Fix - draft)")
    final_path = File.join(@dir, "final.docx")
    rezip_to(final_path)

    # Clone the same document-format settings DocumentGeneratorBase#upload copies
    # from a template onto its generated output ("download", "printing",
    # "force_esign_order", "display_on_page") — this draft is, in the same sense,
    # a document derived from the source template. orignal/template are then
    # forced to true regardless of the source's own values (see below), and the
    # rest of Document.create!'s kwargs override any of these slice carries over.
    settings = @document.attributes.slice("download", "printing", "force_esign_order", "display_on_page")

    Document.create!(
      **settings,
      name: "#{@document.name} #{name_suffix}",
      entity: @document.entity,
      folder: @document.folder,
      owner: @document.owner,
      # Deliberately NOT the source's owner_tag: Document#setup_folder auto-flags
      # template=true whenever owner_tag includes "Template" (e.g. "Commitment
      # Template"), which would put this draft in the fund's template
      # owner_tag-filtered lists (e.g. CapitalCommitmentDocJob's default
      # template scan) alongside the source before a human has reviewed it.
      # template/orignal are set explicitly true instead (regardless of the
      # source's own values) — Document#setup_folder only applies its
      # owner_tag-derived default via `self.template ||= ...`, so an explicit
      # true here is never overridden.
      owner_tag: nil,
      template: true,
      orignal: true,
      user: @document.user,
      from_template: @document,
      file: File.open(final_path, "rb")
    )
  end

  def cleanup!
    FileUtils.remove_entry(@dir) if @dir && Dir.exist?(@dir)
  end

  # Structural (not render-based) early-warning for the "blank page after
  # heading" bug: finds paragraph styles that carry <w:keepNext/> AND are used
  # by a run of CLOSELY-CLUSTERED paragraphs (occurrences no more than
  # +max_gap+ paragraph-indices apart — a numbered sub-clause list typically
  # alternates the styled item with one empty spacer paragraph, so a gap of 2
  # is the norm; +max_gap+ allows a little slack). A style's raw total-use
  # count is NOT enough to flag on by itself — e.g. Heading1 (a genuine,
  # legitimate keepNext use, preventing a top-level section heading being
  # orphaned at the bottom of a page) is used 31 times in Individual.docx, but
  # scattered one-per-section across ~2500 paragraphs, never clustered. A
  # keepNext style reused several times in a tight cluster (e.g. Heading4 on
  # 6 consecutive "X.Y.Z" nested sub-clauses like 5.2.9.1-5.2.9.6) is the
  # repeated-list-item pattern that risks LibreOffice gluing that whole run
  # into one unbreakable block. This is a static XML scan (cheap, always
  # accurate) rather than inferring from rendered PDF text — confirmed on
  # Individual.docx that pdftotext -layout does NOT reliably represent a large
  # visual gap as a proportionally blank page (the page still has its real
  # preceding text plus the page-number footer, so a naive "page has very
  # little text" check misses it entirely).
  def keepnext_repeated_styles(part_name = "word/document.xml", min_cluster: 3, max_gap: 4)
    styles_doc = part("word/styles.xml")
    return [] unless styles_doc

    keepnext_style_ids = styles_doc.xpath("//w:style[@w:type='paragraph']", "w" => W_NS).filter_map do |style|
      style["w:styleId"] if style.at_xpath("w:pPr/w:keepNext", "w" => W_NS)
    end
    return [] if keepnext_style_ids.empty?

    doc = part(part_name)
    return [] unless doc

    indices_by_style = Hash.new { |h, k| h[k] = [] }
    doc.xpath("//w:p", "w" => W_NS).each_with_index do |p, idx|
      sid = p.at_xpath("w:pPr/w:pStyle", "w" => W_NS)&.[]("w:val")
      indices_by_style[sid] << idx if sid && keepnext_style_ids.include?(sid)
    end

    indices_by_style.filter_map do |sid, indices|
      next if indices.size < min_cluster

      start_idx, cluster_len = longest_clustered_run(indices, max_gap)
      { style_id: sid, clustered_count: cluster_len, start_index: start_idx } if cluster_len >= min_cluster
    end
  end

  private

  # Flags pages whose extracted text is suspiciously short — the fingerprint of
  # the "blank page after heading" pagination bug (confirmed live on
  # Individual.docx: a paragraph style's <w:keepNext/> chains several
  # consecutive same-style paragraphs — e.g. Heading4 on clauses 5.2.9.1-
  # 5.2.9.6 — into one unbreakable block; when that block doesn't fit the
  # remaining space on a page, LibreOffice pushes the WHOLE block to the next
  # page instead of splitting it, leaving the gap behind). Without this, an
  # LLM agent has no cheap way to notice the bug in a page-text dump — it would
  # have to read and mentally diff thousands of characters looking for a gap,
  # which a tool-call-budget-constrained loop won't reliably do. The trailing
  # page is excluded: a short/empty final page is a normal document-end
  # artifact, not a pagination bug.
  def detect_blank_pages(text, min_chars: 40)
    pages = text.to_s.split("\f")
    pages.each_with_index.filter_map do |page_text, idx|
      next if idx == pages.size - 1

      stripped = page_text.strip
      next if stripped.length >= min_chars

      next_page_text = pages[idx + 1].to_s.strip
      next_snippet = next_page_text.lines.first&.strip.presence || next_page_text[0, 80]
      { page: idx + 1, chars: stripped.length, next_page_starts_with: next_snippet }
    end
  end

  # Given sorted paragraph indices where a style occurs, returns [start_index,
  # length] of the longest run where consecutive occurrences are within
  # +max_gap+ of each other.
  def longest_clustered_run(indices, max_gap)
    best_start = indices.first
    best_len = 1
    run_start = indices.first
    run_len = 1

    indices.each_cons(2) do |a, b|
      if (b - a) <= max_gap
        run_len += 1
      else
        best_start, best_len = run_start, run_len if run_len > best_len
        run_start = b
        run_len = 1
      end
    end
    best_start, best_len = run_start, run_len if run_len > best_len

    [best_start, best_len]
  end

  def validate_sablon_expression!(expression)
    return if expression.start_with?("=") || expression.match?(VALID_SABLON_TAIL)

    raise ArgumentError,
          "Invalid Sablon expression #{expression.inspect}. A standalone merge-field paragraph must be " \
          "either a value insertion ('=expr') or end with one of Sablon's real operations: ':if', " \
          "':elsif', ':elseIf', ':else', ':endIf', ':each(item)', ':endEach'. There is no ':unless' in " \
          "Sablon — an unrecognized operation is NOT stripped at render time, it prints as literal " \
          "garbage text and the enclosed block still renders unconditionally. To show a block only when " \
          "a condition is false, use the negated boolean with ':if' (e.g. 'foo.non_individual?:if' ... " \
          "':endIf'), or 'X:if' ... 'X:else' ... ':endIf'."
  end

  # Builds the 5-run Word complex-field sequence (begin/instrText/separate/
  # display/end) as sibling <w:r> nodes bound to `doc` — the exact structure
  # Word itself uses for its own «=...» merge fields, and the only form
  # Sablon's ComplexField parser (lib/sablon/parser/mail_merge.rb) recognizes.
  def merge_field_runs(doc, expression, display_text)
    begin_run = Nokogiri::XML::Node.new("w:r", doc)
    begin_run.add_child(Nokogiri::XML::Node.new("w:fldChar", doc).tap { |n| n["w:fldCharType"] = "begin" })

    instr_run = Nokogiri::XML::Node.new("w:r", doc)
    instr_text = Nokogiri::XML::Node.new("w:instrText", doc)
    instr_text["xml:space"] = "preserve"
    instr_text.content = " MERGEFIELD  #{expression}  \\* MERGEFORMAT "
    instr_run.add_child(instr_text)

    separate_run = Nokogiri::XML::Node.new("w:r", doc)
    separate_run.add_child(Nokogiri::XML::Node.new("w:fldChar", doc).tap { |n| n["w:fldCharType"] = "separate" })

    display_run = Nokogiri::XML::Node.new("w:r", doc)
    t = Nokogiri::XML::Node.new("w:t", doc)
    t.content = display_text
    display_run.add_child(t)

    end_run = Nokogiri::XML::Node.new("w:r", doc)
    end_run.add_child(Nokogiri::XML::Node.new("w:fldChar", doc).tap { |n| n["w:fldCharType"] = "end" })

    [begin_run, instr_run, separate_run, display_run, end_run]
  end

  def validate_part!(part_name)
    return if EDITABLE_PARTS.include?(part_name)

    raise InvalidPart, "#{part_name} is not an editable part. Allowed: #{EDITABLE_PARTS.join(', ')}"
  end

  def read_raw_entry(docx_path, part_name)
    Zip::File.open(docx_path) do |zip|
      zip.find_entry(part_name)&.get_input_stream&.read
    end
  end
end
