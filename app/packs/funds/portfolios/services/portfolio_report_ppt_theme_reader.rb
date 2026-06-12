require 'zip'
require 'nokogiri'

# Reads colour and font information from a .pptx style-reference file.
# Only `ppt/theme/theme1.xml` is inspected; no slide content is read.
#
# Usage:
#   reader = PortfolioReportPptThemeReader.new("/tmp/style.pptx")
#   reader.accent1   #=> "047857"  (hex, no #)
#   reader.font      #=> "Calibri"
#   reader.overrides #=> { accent1: "047857", font: "Calibri" }
class PortfolioReportPptThemeReader
  COLOR_SLOTS = %w[dk1 lt1 dk2 lt2 accent1 accent2 accent3 accent4 accent5 accent6].freeze

  def initialize(pptx_path)
    @pptx_path = pptx_path
    @theme_xml = nil
  end

  # Returns a hash of { slot => hex_string } for every slot that has an srgbClr.
  def colors
    @colors ||= begin
      result = {}
      xml = load_theme
      if xml
        xml.remove_namespaces!
        COLOR_SLOTS.each do |slot|
          node = xml.at_xpath("//clrScheme/#{slot}/srgbClr")
          result[slot] = node["val"].upcase if node
        end
      end
      result
    end
  end

  # Convenience: the primary accent colour (accent1), or nil.
  def accent1
    colors["accent1"]
  end

  # Major font name from the theme's fontScheme, or nil.
  def font
    @font ||= begin
      xml = load_theme
      if xml
        xml.remove_namespaces!
        xml.at_xpath("//fontScheme/majorFont/latin")&.attr("typeface")
      end
    end
  end

  # Returns the raw theme XML string (for injecting verbatim into generated PPTX).
  def raw_theme_xml
    load_theme_raw
  end

  # Combined overrides hash passed to the PPT service.
  def overrides
    h = {}
    h[:accent1]   = accent1 if accent1
    h[:font]      = font    if font
    h[:theme_xml] = raw_theme_xml if raw_theme_xml
    h
  end

  private

  def load_theme
    raw = load_theme_raw
    raw ? Nokogiri::XML(raw) : nil
  rescue StandardError => e
    Rails.logger.warn { "[PptThemeReader] Could not parse theme: #{e.message}" }
    nil
  end

  def load_theme_raw
    return @theme_raw if defined?(@theme_raw)

    @theme_raw = Zip::File.open(@pptx_path) do |zip|
      entry = zip.find_entry("ppt/theme/theme1.xml")
      entry&.get_input_stream&.read
    end
  rescue StandardError => e
    Rails.logger.warn { "[PptThemeReader] Could not open PPTX: #{e.message}" }
    @theme_raw = nil
  end
end
