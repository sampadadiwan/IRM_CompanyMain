require "zip"
require "nokogiri"

# Prevents LibreOffice from changing fonts or indentation during DOCX→PDF
# conversion by "baking in" the resolved Word style properties as direct
# paragraph/run formatting.
#
# Root cause:
#   DOCX files rely on a paragraph-style inheritance chain (basedOn) to define
#   fonts, sizes, and indentation.  LibreOffice sometimes misreads or ignores
#   custom styles in that chain, falling back to its own defaults (e.g. wrong
#   indent, Liberation Serif instead of Times New Roman, wrong font size).
#
#   By adding explicit <w:ind>, <w:tabs>, <w:rFonts>, <w:sz> elements directly
#   on each paragraph/run that lacks them, we give LibreOffice the values it
#   needs without changing what Word would display (direct formatting always
#   wins over style-inherited formatting in OOXML).
#
# What we preserve:
#   Paragraph level: indentation (w:ind), tab stops (w:tabs), paragraph
#   spacing (w:spacing), justification (w:jc).
#   Run level: font family (w:rFonts), font sizes (w:sz, w:szCs).
#
# Font mapping:
#   Linux servers often lack Microsoft fonts.  Liberation fonts are the
#   standard metric-compatible substitutes used by LibreOffice on Linux.
#   Mapping here avoids LibreOffice picking an arbitrary substitute that has
#   different character metrics (which reflows text and changes pagination).
class DocxFormattingPreserver
  # Microsoft font → metric-compatible Liberation substitute installed by
  # default on most Linux distros (via fonts-liberation / liberation-fonts).
  FONT_MAP = {
    "Times New Roman" => "Liberation Serif",
    "Arial" => "Liberation Sans",
    "Courier New" => "Liberation Mono",
    "Calibri" => "Carlito",
    "Cambria" => "Caladea",
    "Cambria Math" => "Caladea"
  }.freeze
  W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main".freeze

  # Paragraph-level property tag names we want to ensure are explicit
  PARA_TAGS = %w[ind tabs spacing jc].freeze
  # Run-level property tag names we want to ensure are explicit
  RUN_TAGS  = %w[rFonts sz szCs].freeze

  def self.apply!(docx_path, map_fonts: true)
    new(docx_path, map_fonts: map_fonts).apply!
  end

  def initialize(docx_path, map_fonts: true)
    @docx_path = docx_path
    @map_fonts = map_fonts
  end

  def apply!
    tmp_path = "#{@docx_path}.fmt_fix.tmp"

    Zip::File.open(@docx_path) do |zip|
      styles_xml = read_entry(zip, "word/styles.xml")
      doc_xml    = read_entry(zip, "word/document.xml")
      num_xml    = read_entry(zip, "word/numbering.xml")

      unless styles_xml && doc_xml
        copy_zip(zip, tmp_path)
        FileUtils.mv(tmp_path, @docx_path)
        return @docx_path
      end

      styles_doc = Nokogiri::XML(styles_xml, &:strict)
      body_doc   = Nokogiri::XML(doc_xml, &:strict)
      num_doc    = num_xml ? Nokogiri::XML(num_xml, &:strict) : nil

      @style_cache     = build_style_cache(styles_doc)
      @level_tab_cache = num_doc ? build_level_tab_cache(num_doc) : {}

      patch_document!(body_doc)

      # Rewrite abstractNum level pPr in numbering.xml so LibreOffice reads
      # the correct ind/tab values directly from the list definition — paragraph
      # overrides alone are not reliably honoured by LibreOffice for num tabs.
      if num_doc
        dominant = patch_numbering_levels!(body_doc, num_doc)
        # Stamp every list paragraph with an explicit w:ind so that paragraph-style
        # w:firstLine values (e.g. from "Bod" style) cannot bleed through.
        # LibreOffice reads firstLine from the style chain if the paragraph has no
        # direct ind, causing the first line to appear more indented than wrap lines.
        enforce_list_ind!(body_doc, num_doc, dominant) if dominant&.any?
      end

      Zip::OutputStream.open(tmp_path) do |out|
        zip.each do |entry|
          next if entry.directory?

          out.put_next_entry(
            entry.name, nil, nil,
            Zip::Entry::DEFLATED,
            Zlib::DEFAULT_COMPRESSION
          )
          case entry.name
          when "word/document.xml"
            out.write(body_doc.to_xml(encoding: "UTF-8"))
          when "word/numbering.xml"
            out.write(num_doc ? num_doc.to_xml(encoding: "UTF-8") : entry.get_input_stream.read)
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

  # -----------------------------------------------------------------------
  # Numbering level tab cache
  # -----------------------------------------------------------------------

  # Returns "numId_ilvl" => [tab_pos, ...] mapping of all w:val="num" tab
  # positions defined at the abstract list level for that (numId, ilvl).
  # We use this to add w:val="clear" entries in paragraphs so LibreOffice
  # cannot fall back to the list-level tab when the paragraph has a different
  # (or no) num tab of its own.
  def build_level_tab_cache(num_doc)
    ns = { "w" => W_NS }

    # abstractNumId => ilvl => [num tab positions]
    abstract_tabs = {}
    num_doc.xpath("//w:abstractNum", ns).each do |abn|
      abid = wattr(abn, "abstractNumId")
      abstract_tabs[abid] = {}
      abn.xpath("w:lvl", ns).each do |lvl|
        ilvl  = wattr(lvl, "ilvl")
        pPr   = lvl.at_xpath("w:pPr", ns)
        next unless pPr

        tabs = pPr.at_xpath("w:tabs", ns)
        next unless tabs

        positions = tabs.xpath("w:tab", ns).filter_map do |tab|
          wattr(tab, "pos")&.to_i if wattr(tab, "val") == "num"
        end
        abstract_tabs[abid][ilvl] = positions unless positions.empty?
      end
    end

    # numId => abstractNumId
    num_to_abstract = {}
    num_doc.xpath("//w:num", ns).each do |num|
      nid = wattr(num, "numId")
      ab  = num.at_xpath("w:abstractNumId", ns)
      num_to_abstract[nid] = wattr(ab, "val") if nid && ab
    end

    # Build flat cache: "numId_ilvl" => [positions]
    cache = {}
    num_to_abstract.each do |nid, abid|
      (abstract_tabs[abid] || {}).each do |ilvl, positions|
        cache["#{nid}_#{ilvl}"] = positions
      end
    end
    cache
  end

  # For each (abstractNumId, ilvl) that has paragraphs with a different
  # w:ind[@left] than the list level defines, update the list level's
  # w:pPr > w:ind and w:pPr > w:tabs to match the paragraph values.
  # LibreOffice reads number placement (the tab after the label) from the
  # list level definition regardless of paragraph overrides, so fixing the
  # source is the only reliable approach.
  def patch_numbering_levels!(body_doc, num_doc)
    ns = { "w" => W_NS }

    # numId -> abstractNumId from numbering.xml
    num_to_abstract = {}
    num_doc.xpath("//w:num", ns).each do |num|
      nid = wattr(num, "numId")
      ab  = num.at_xpath("w:abstractNumId", ns)
      num_to_abstract[nid] = wattr(ab, "val") if nid && ab
    end

    # Collect dominant ind values per (abstractNumId, ilvl) from document paragraphs
    # Use a tally: key -> { left => count, hanging => count }
    tally = Hash.new { |h, k| h[k] = Hash.new(0) }

    body_doc.xpath("//w:body//w:p", ns).each do |para|
      pPr = para.at_xpath("w:pPr", ns)
      next unless pPr

      numPr = pPr.at_xpath("w:numPr", ns)
      next unless numPr

      nid_el  = numPr.at_xpath("w:numId",  ns)
      ilvl_el = numPr.at_xpath("w:ilvl",   ns)
      next unless nid_el && ilvl_el

      nid   = wattr(nid_el,  "val")
      ilvl  = wattr(ilvl_el, "val")
      next if nid == "0"

      abstract_id = num_to_abstract[nid]
      next unless abstract_id

      ind = pPr.at_xpath("w:ind", ns)
      next unless ind

      left    = wattr(ind, "left")
      hanging = wattr(ind, "hanging")
      next unless left

      # If paragraph ind specifies left but omits hanging, resolve hanging from the abstractNum level
      if hanging.nil? || hanging.empty?
        lvl_el = num_doc.at_xpath("//w:abstractNum[@w:abstractNumId='#{abstract_id}']/w:lvl[@w:ilvl='#{ilvl}']", ns)
        lvl_ind = lvl_el&.at_xpath("w:pPr/w:ind", ns)
        hanging = wattr(lvl_ind, "hanging") if lvl_ind
      end

      key = "#{abstract_id}_#{ilvl}"
      tally[key]["#{left}|#{hanging}"] += 1
    end

    # Build dominant ind per (abstractNumId, ilvl)
    dominant = {}
    tally.each do |key, counts|
      best = counts.max_by { |_, c| c }&.first
      next unless best

      left_s, hanging_s = best.split("|")
      hang_val = (hanging_s && !hanging_s.empty?) ? hanging_s.to_i : 0
      if hang_val.zero?
        ab_id, ilvl_val = key.split("_")
        lvl_el = num_doc.at_xpath("//w:abstractNum[@w:abstractNumId='#{ab_id}']/w:lvl[@w:ilvl='#{ilvl_val}']", ns)
        lvl_ind = lvl_el&.at_xpath("w:pPr/w:ind", ns)
        orig_hang = wattr(lvl_ind, "hanging")&.to_i
        hang_val = orig_hang if orig_hang&.positive?
      end
      dominant[key] = { left: left_s.to_i, hanging: hang_val }
      # Log minority values that are being discarded so unexpected overwrites are visible in logs
      discarded = counts.keys.reject { |k| k == best }
      next unless discarded.any?

      Rails.logger.debug do
        "[DocxFormattingPreserver] abstractNum #{key}: dominant ind=#{best} " \
          "(#{counts[best]} para(s)); discarding minority: #{discarded.join(', ')}"
      end
    end

    return {} if dominant.empty?

    # Update each abstractNum level whose ind differs from what paragraphs use
    num_doc.xpath("//w:abstractNum", ns).each do |abn|
      abstract_id = wattr(abn, "abstractNumId")
      abn.xpath("w:lvl", ns).each do |lvl|
        ilvl = wattr(lvl, "ilvl")
        key  = "#{abstract_id}_#{ilvl}"
        dom  = dominant[key]
        next unless dom

        # Get or create pPr under w:lvl
        pPr = lvl.at_xpath("w:pPr", ns)
        if pPr.nil?
          frag = Nokogiri::XML::DocumentFragment.parse("<w:pPr xmlns:w=\"#{W_NS}\"/>")
          pPr  = frag.first_element_child
          # Insert pPr after w:start / w:numFmt / w:lvlText (before w:rPr if any)
          rPr = lvl.at_xpath("w:rPr", ns)
          rPr ? rPr.add_previous_sibling(pPr) : lvl.add_child(pPr)
        end

        # Remove existing ind and tabs so we can re-add in OOXML canonical order
        # (w:tabs must precede w:ind inside w:pPr)
        pPr.at_xpath("w:tabs", ns)&.remove
        pPr.at_xpath("w:ind",  ns)&.remove

        # Add w:tabs first, then w:ind
        tabs_frag = Nokogiri::XML::DocumentFragment.parse(
          "<w:tabs xmlns:w=\"#{W_NS}\">" \
          "<w:tab w:val=\"num\" w:pos=\"#{dom[:left]}\"/>" \
          "</w:tabs>"
        )
        pPr.add_child(tabs_frag.first_element_child)

        ind_frag = Nokogiri::XML::DocumentFragment.parse(
          "<w:ind xmlns:w=\"#{W_NS}\" w:left=\"#{dom[:left]}\" w:hanging=\"#{dom[:hanging]}\"/>"
        )
        pPr.add_child(ind_frag.first_element_child)

        Rails.logger.debug do
          "[DocxFormattingPreserver] abstractNum=#{abstract_id} ilvl=#{ilvl} " \
            "ind updated to left=#{dom[:left]} hanging=#{dom[:hanging]}"
        end
      end
    end

    dominant
  end

  # Stamp every list paragraph with an explicit w:ind so LibreOffice cannot inherit
  # w:firstLine from the paragraph style chain (e.g. "Bod" style has w:firstLine="720").
  # LO applies the style's firstLine when the paragraph has no direct ind, causing the
  # first line to appear more indented than the wrap lines.
  #
  # For paragraphs WITHOUT a direct ind, we pick the ind values in priority order:
  #   1. dominant[abstractNum_ilvl] — most common values seen across all paragraphs
  #   2. abstractNum level's current ind — already corrected by patch_numbering_levels!
  # We fall through to the abstractNum level so paragraphs at levels with no direct-ind
  # contributors still get protected against style firstLine bleed.
  def enforce_list_ind!(body_doc, num_doc, dominant)
    ns = { "w" => W_NS }

    # Build numId -> abstractNumId mapping
    num_to_abstract = {}
    num_doc.xpath("//w:num", ns).each do |num|
      nid = wattr(num, "numId")
      ab  = num.at_xpath("w:abstractNumId", ns)
      num_to_abstract[nid] = wattr(ab, "val") if nid && ab
    end

    # Build abstractNum_ilvl -> {left, hanging} from the (already-patched) numbering.xml
    abstract_lvl_ind = {}
    num_doc.xpath("//w:abstractNum", ns).each do |abn|
      abid = wattr(abn, "abstractNumId")
      abn.xpath("w:lvl", ns).each do |lvl|
        ilvl = wattr(lvl, "ilvl")
        ind  = lvl.at_xpath("w:pPr/w:ind", ns)
        next unless ind

        left = wattr(ind, "left")&.to_i
        hang = wattr(ind, "hanging").to_i
        abstract_lvl_ind["#{abid}_#{ilvl}"] = { left: left, hanging: hang } if left
      end
    end

    body_doc.xpath("//w:body//w:p", ns).each do |para|
      pPr = para.at_xpath("w:pPr", ns)
      next unless pPr

      numPr = pPr.at_xpath("w:numPr", ns)
      next unless numPr

      nid_el  = numPr.at_xpath("w:numId",  ns)
      ilvl_el = numPr.at_xpath("w:ilvl",   ns)
      next unless nid_el && ilvl_el

      nid  = wattr(nid_el,  "val")
      ilvl = wattr(ilvl_el, "val")
      next if nid == "0"

      abstract_id = num_to_abstract[nid]
      next unless abstract_id

      ind = pPr.at_xpath("w:ind", ns)
      if ind
        # Has direct ind — strip firstLine. Cover both the standard namespaced
        # form (w:firstLine) and the rare unqualified form that some editors
        # emit without a namespace prefix.
        ind.attribute_with_ns("firstLine", W_NS)&.remove
        ind.attribute_with_ns("firstLine", nil)&.remove

        # Also correct left/hanging, but ONLY when the paragraph's OWN ind
        # already specifies BOTH attributes and they're an outlier against the
        # dominant indentation every other paragraph at this list level uses.
        # Confirmed live: one paragraph ("2.24.1.") had its own explicit
        # left=1440 hanging=589 — too small for its own number label — while
        # every sibling at the same numId/ilvl correctly used hanging=720.
        # The label overshot into the body text's tab stop, producing a large
        # visible gap; correcting a COMPLETE-but-wrong pair like this is safe.
        #
        # A paragraph with only ONE of the two attributes (e.g. <w:ind
        # w:hanging="731"/>, no w:left) is a DIFFERENT, deliberate pattern —
        # it's relying on inheriting the missing attribute from the abstractNum
        # level or style chain, not an authoring mistake. An earlier version of
        # this fix force-completed such partial inds with the tally's dominant
        # values regardless, which silently broke a paragraph that was already
        # rendering correctly (confirmed live: introduced a new visible gap at
        # clause 2.10.1 that did not exist in the original template). Leave
        # partial inds alone — only firstLine gets stripped for them, same as
        # every direct-ind paragraph.
        own_left = wattr(ind, "left")
        own_hanging = wattr(ind, "hanging")
        if own_left && own_hanging
          dom = dominant["#{abstract_id}_#{ilvl}"] || abstract_lvl_ind["#{abstract_id}_#{ilvl}"]
          if dom && (own_left.to_i != dom[:left] || own_hanging.to_i != dom[:hanging])
            ind["w:left"] = dom[:left].to_s
            ind["w:hanging"] = dom[:hanging].to_s
          end
        end
      else
        # No direct ind — add one to block style-chain firstLine inheritance.
        # Prefer dominant values; fall back to the abstractNum level's own ind.
        dom = dominant["#{abstract_id}_#{ilvl}"] || abstract_lvl_ind["#{abstract_id}_#{ilvl}"]
        next unless dom

        frag = Nokogiri::XML::DocumentFragment.parse(
          "<w:ind xmlns:w=\"#{W_NS}\" w:left=\"#{dom[:left]}\" w:hanging=\"#{dom[:hanging]}\"/>"
        )
        pPr.add_child(frag.first_element_child)
      end
    end
  end

  # -----------------------------------------------------------------------
  # Style resolution
  # -----------------------------------------------------------------------

  # Returns two caches:
  #   para_cache:  styleId => { pPr: {tag=>node}, rPr: {tag=>node} }
  #   char_cache:  styleId => { rPr: {tag=>node} }
  def build_style_cache(styles_doc)
    ns = { "w" => W_NS }
    raw_para = {}
    raw_char = {}

    # Document defaults (lowest priority for paragraph styles)
    def_rPr = styles_doc.at_xpath("//w:docDefaults/w:rPrDefault/w:rPr", ns)
    raw_para["__defaults__"] = { based_on: nil, pPr: nil, rPr: def_rPr }

    styles_doc.xpath("//w:style", ns).each do |style|
      stype  = wattr(style, "type")
      sid    = wattr(style, "styleId")
      next unless sid

      based  = style.at_xpath("w:basedOn", ns)
      rPr    = style.at_xpath("w:rPr", ns)

      if stype == "paragraph"
        pPr = style.at_xpath("w:pPr", ns)
        raw_para[sid] = {
          based_on: based ? wattr(based, "val") : "__defaults__",
          pPr: pPr,
          rPr: rPr
        }
      elsif stype == "character"
        raw_char[sid] = {
          based_on: based ? wattr(based, "val") : nil,
          rPr: rPr
        }
      end
    end

    # Resolve paragraph style inheritance
    para_resolved = {}
    raw_para.each_key { |sid| resolve_para_style!(sid, raw_para, para_resolved) }

    # Resolve character style inheritance (rPr only)
    char_resolved = {}
    raw_char.each_key { |sid| resolve_char_style!(sid, raw_char, char_resolved) }

    @char_cache = char_resolved
    para_resolved
  end

  def resolve_para_style!(sid, raw, resolved)
    return resolved[sid] if resolved.key?(sid)

    info = raw[sid]
    unless info
      resolved[sid] = { pPr: {}, rPr: {} }
      return resolved[sid]
    end

    resolved[sid] = :resolving # cycle guard
    parent = info[:based_on] ? resolve_para_style!(info[:based_on], raw, resolved) : { pPr: {}, rPr: {} }
    parent = { pPr: {}, rPr: {} } if parent == :resolving

    pPr_map = parent[:pPr].dup
    rPr_map = parent[:rPr].dup
    extract_props(info[:pPr], PARA_TAGS).each { |tag, node| pPr_map[tag] = node }
    extract_props(info[:rPr], RUN_TAGS).each  { |tag, node| rPr_map[tag] = node }

    resolved[sid] = { pPr: pPr_map, rPr: rPr_map }
  end

  def resolve_char_style!(sid, raw, resolved)
    return resolved[sid] if resolved.key?(sid)

    info = raw[sid]
    unless info
      resolved[sid] = { rPr: {} }
      return resolved[sid]
    end
    resolved[sid] = :resolving
    parent = info[:based_on] ? resolve_char_style!(info[:based_on], raw, resolved) : { rPr: {} }
    parent = { rPr: {} } if parent == :resolving
    rPr_map = parent[:rPr].dup
    extract_props(info[:rPr], RUN_TAGS).each { |tag, node| rPr_map[tag] = node }
    resolved[sid] = { rPr: rPr_map }
  end

  # Extract only the tags we care about from an XML properties element
  def extract_props(xml_el, tags)
    return {} unless xml_el

    ns = { "w" => W_NS }
    tags.each_with_object({}) do |tag, h|
      node = xml_el.at_xpath("w:#{tag}", ns)
      h[tag] = node.dup if node
    end
  end

  # -----------------------------------------------------------------------
  # Document patching
  # -----------------------------------------------------------------------

  def patch_document!(body_doc)
    ns = { "w" => W_NS }
    body_doc.xpath("//w:body//w:p", ns).each do |para|
      pPr = para.at_xpath("w:pPr", ns)
      next unless pPr

      style_el  = pPr.at_xpath("w:pStyle", ns)
      style_id  = style_el ? wattr(style_el, "val") : "Normal"
      resolved  = @style_cache[style_id] || @style_cache["Normal"] || { pPr: {}, rPr: {} }

      # For list paragraphs skip baking ind and tabs — indentation is owned by the
      # abstractNum level in numbering.xml (already corrected by patch_numbering_levels!).
      # Injecting a style's w:ind (e.g. Bod style has w:firstLine="720") causes
      # LibreOffice to combine it with the list-level left, shifting the first line
      # further right than the wrap lines.
      list_para = pPr.at_xpath("w:numPr", ns)
      bake_tags = list_para ? PARA_TAGS - %w[ind tabs] : PARA_TAGS
      bake_props!(pPr, resolved[:pPr], bake_tags)

      if list_para
        # Strip firstLine from any existing direct w:ind on list paragraphs —
        # prevents original-template firstLine values from persisting.
        pPr.at_xpath("w:ind", ns)&.tap do |i|
          i.attribute_with_ns("firstLine", W_NS)&.remove
          i.attribute_with_ns("firstLine", nil)&.remove
        end

        # Strip any leading w:tab from EVERY run of a list paragraph, not just the
        # first. LibreOffice's list mechanism auto-inserts a tab after the number
        # label (landing on the num tab stop); a leading w:tab on the first run's
        # content duplicates that and jumps to the *next* tab stop, pushing text
        # further right than wrap lines — that's the original, narrower fix.
        # But the same artifact also shows up mid-paragraph: when two originally
        # separate numbered clauses get merged into one paragraph (or a clause is
        # re-typed with its old leading tab left in place), the leftover tab lands
        # as the leading content of a LATER run instead of the first — e.g.
        # "<w:r><w:t>...first sentence. </w:t></w:r><w:r><w:tab/><w:t>Second
        # sentence...</w:t></w:r>" — producing a large unwanted gap mid-sentence.
        # Confirmed live on clause 5.2.6 of MessedUpDocTemplate.docx (see
        # docs/modules/documents/template_fix_agent_handover_note.md #Issue 3): the stray tab
        # sat on the paragraph's SECOND run, which the single-first-run check
        # above never looked at. A run-leading tab is never legitimate in a list
        # paragraph — the number's own tab stop already positions the first line,
        # and Word/LibreOffice never place a tab as a run's first child except as
        # this duplication artifact — so it's safe to strip unconditionally.
        para.xpath("w:r", ns).each do |run|
          first_content = run.xpath("w:*", ns).find { |c| c.name != "rPr" }
          first_content.remove if first_content&.name == "tab"
        end
      end

      # Resolve run-level defaults for this paragraph style
      para_rPr_defaults = resolved[:rPr]

      # Bake missing run-level properties into each run
      para.xpath("w:r", ns).each do |run|
        rPr = run.at_xpath("w:rPr", ns)

        # Inherit paragraph-style rPr as base, then override with character style
        char_style_el = rPr&.at_xpath("w:rStyle", ns)
        char_style_id = char_style_el ? wattr(char_style_el, "val") : nil
        char_rPr      = (@char_cache[char_style_id] || { rPr: {} })[:rPr]

        # Effective defaults: paragraph-style rPr, overridden by char-style rPr
        effective_defaults = para_rPr_defaults.merge(char_rPr)

        if rPr.nil?
          # No run properties element at all — build a minimal one.
          # Nokogiri re-parents nodes automatically on prepend_child; no adopt needed.
          frag = Nokogiri::XML::DocumentFragment.parse(
            "<w:rPr xmlns:w=\"#{W_NS}\"/>"
          )
          rPr = frag.first_element_child
          run.prepend_child(rPr)
        end

        bake_props!(rPr, effective_defaults, RUN_TAGS)

        # Apply font mapping if requested
        apply_font_map!(rPr) if @map_fonts
      end
    end
  end

  # Ensure numbered-list paragraphs have exactly one w:val="num" tab stop
  # sitting at their w:ind[@left] position, and that all other num-tab
  # positions (whether in the paragraph or inherited from the abstract list
  # level in numbering.xml) are explicitly cleared.
  #
  # Two LibreOffice bugs drive this fix:
  #   1. Multiple num tabs in the paragraph — LO picks the first that fits,
  #      so items with wider labels land on the wrong (later) stop.
  #   2. Missing clear for the abstractNum level's built-in num tab — LO can
  #      fall back to the list-level tab even when the paragraph overrides
  #      ind[@left] with a larger value, producing cramped spacing.
  def normalize_num_tabs!(pPr)
    ns  = { "w" => W_NS }
    ind = pPr.at_xpath("w:ind", ns)
    return unless ind

    left_pos = wattr(ind, "left")&.to_i
    return unless left_pos

    # Fetch list-level num-tab positions from numbering.xml cache
    numPr   = pPr.at_xpath("w:numPr", ns)
    nid_el  = numPr&.at_xpath("w:numId", ns)
    ilvl_el = numPr&.at_xpath("w:ilvl", ns)
    nid     = nid_el  ? wattr(nid_el,  "val") : nil
    ilvl    = ilvl_el ? wattr(ilvl_el, "val") : nil
    level_tab_positions = nid && ilvl ? (@level_tab_cache["#{nid}_#{ilvl}"] || []) : []

    # Positions that must be cleared: all list-level num tabs that differ from left_pos
    clear_positions = level_tab_positions.reject { |p| p == left_pos }

    # Get or create the w:tabs element
    tabs_el = pPr.at_xpath("w:tabs", ns)
    if tabs_el.nil?
      frag    = Nokogiri::XML::DocumentFragment.parse("<w:tabs xmlns:w=\"#{W_NS}\"/>")
      tabs_el = frag.first_element_child
      # Insert before w:ind to keep canonical OOXML ordering
      ind.add_previous_sibling(tabs_el)
    end

    # Remove all existing num tabs in the paragraph (clean slate)
    tabs_el.xpath("w:tab", ns).each do |tab|
      tab.remove if wattr(tab, "val") == "num"
    end

    # Add clear entries for every list-level num-tab position we're overriding,
    # unless the paragraph already has a clear there
    clear_positions.each do |cpos|
      already_cleared = tabs_el.xpath("w:tab", ns).any? do |tab|
        wattr(tab, "val") == "clear" && wattr(tab, "pos")&.to_i == cpos
      end
      next if already_cleared

      frag = Nokogiri::XML::DocumentFragment.parse(
        "<w:tab xmlns:w=\"#{W_NS}\" w:val=\"clear\" w:pos=\"#{cpos}\"/>"
      )
      tabs_el.add_child(frag.first_element_child)
    end

    # Add exactly one num tab at left_pos
    frag = Nokogiri::XML::DocumentFragment.parse(
      "<w:tab xmlns:w=\"#{W_NS}\" w:val=\"num\" w:pos=\"#{left_pos}\"/>"
    )
    tabs_el.add_child(frag.first_element_child)

    # Clean up if somehow left empty (shouldn't happen but be defensive)
    tabs_el.remove if tabs_el.children.none?(&:element?)
  end

  # For each tag in +tags+: if +target_el+ doesn't already have it, add the
  # resolved node from +defaults+.
  def bake_props!(target_el, defaults, tags)
    ns = { "w" => W_NS }
    tags.each do |tag|
      next if target_el.at_xpath("w:#{tag}", ns) # already explicit

      node = defaults[tag]
      next unless node

      target_el.add_child(node.dup)
    end
  end

  # Replace Microsoft font names with metric-compatible Liberation equivalents
  # so LibreOffice finds the font instead of substituting an arbitrary one.
  def apply_font_map!(rPr)
    ns = { "w" => W_NS }
    fonts_el = rPr.at_xpath("w:rFonts", ns)
    return unless fonts_el

    %w[ascii hAnsi eastAsia cs].each do |attr|
      full_attr = "#{W_NS}#{attr}"
      val = fonts_el[full_attr]
      next unless val

      mapped = FONT_MAP[val]
      fonts_el[full_attr] = mapped if mapped
    end
  end

  # -----------------------------------------------------------------------
  # Helpers
  # -----------------------------------------------------------------------

  def wattr(el, name)
    el["#{W_NS}#{name}"] || el["w:#{name}"]
  end

  def read_entry(zip, name)
    entry = zip.find_entry(name)
    entry&.get_input_stream&.read
  end

  def copy_zip(zip, tmp_path)
    Zip::OutputStream.open(tmp_path) do |out|
      zip.each do |entry|
        next if entry.directory?

        out.put_next_entry(entry.name, nil, nil, Zip::Entry::DEFLATED, Zlib::DEFAULT_COMPRESSION)
        out.write(entry.get_input_stream.read)
      end
    end
  end
end
