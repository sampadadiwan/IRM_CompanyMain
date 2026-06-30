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
    "Arial"           => "Liberation Sans",
    "Courier New"     => "Liberation Mono",
    "Calibri"         => "Carlito",
    "Cambria"         => "Caladea",
    "Cambria Math"    => "Caladea"
  }.freeze
  W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

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

      styles_doc = Nokogiri::XML(styles_xml) { |c| c.strict }
      body_doc   = Nokogiri::XML(doc_xml)    { |c| c.strict }
      num_doc    = num_xml ? Nokogiri::XML(num_xml) { |c| c.strict } : nil

      @style_cache     = build_style_cache(styles_doc)
      @level_tab_cache = num_doc ? build_level_tab_cache(num_doc) : {}

      patch_document!(body_doc)

      # Rewrite abstractNum level pPr in numbering.xml so LibreOffice reads
      # the correct ind/tab values directly from the list definition — paragraph
      # overrides alone are not reliably honoured by LibreOffice for num tabs.
      patch_numbering_levels!(body_doc, num_doc) if num_doc

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
        tabs  = pPr.at_xpath("w:tabs", ns)
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
      numPr  = pPr.at_xpath("w:numPr", ns)
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

      key = "#{abstract_id}_#{ilvl}"
      tally[key]["#{left}|#{hanging}"] += 1
    end

    # Build dominant ind per (abstractNumId, ilvl)
    dominant = {}
    tally.each do |key, counts|
      best = counts.max_by { |_, c| c }&.first
      next unless best
      left_s, hanging_s = best.split("|")
      dominant[key] = { left: left_s.to_i, hanging: hanging_s.to_i }
      # Log minority values that are being discarded so unexpected overwrites are visible in logs
      discarded = counts.keys.reject { |k| k == best }
      if discarded.any?
        Rails.logger.debug do
          "[DocxFormattingPreserver] abstractNum #{key}: dominant ind=#{best} " \
            "(#{counts[best]} para(s)); discarding minority: #{discarded.join(', ')}"
        end
      end
    end

    return if dominant.empty?

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
          pPr:      pPr,
          rPr:      rPr
        }
      elsif stype == "character"
        raw_char[sid] = {
          based_on: based ? wattr(based, "val") : nil,
          rPr:      rPr
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

    resolved[sid] = :resolving  # cycle guard
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

      # Bake missing paragraph-level properties
      bake_props!(pPr, resolved[:pPr], PARA_TAGS)

      # For numbered-list paragraphs: remove stale w:val="num" tab stops that
      # don't match the paragraph's own w:ind[@left].  LibreOffice picks the
      # first "num" tab whose position fits the rendered label width, so a rogue
      # earlier tab causes the text-start position to jump around as the label
      # grows (e.g. "1.1.9." vs "1.1.10.").
      normalize_num_tabs!(pPr) if pPr.at_xpath("w:numPr", ns)

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
    level_tab_positions = (nid && ilvl) ? (@level_tab_cache["#{nid}_#{ilvl}"] || []) : []

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
      unless already_cleared
        frag = Nokogiri::XML::DocumentFragment.parse(
          "<w:tab xmlns:w=\"#{W_NS}\" w:val=\"clear\" w:pos=\"#{cpos}\"/>"
        )
        tabs_el.add_child(frag.first_element_child)
      end
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
      next if target_el.at_xpath("w:#{tag}", ns)  # already explicit
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
