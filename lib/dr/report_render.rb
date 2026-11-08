# frozen_string_literal: true

require "erb"

module Dr
  # Turns a Dr::ReportModel into the DR run report's HTML and Markdown (openspec
  # dr-drill-report-redesign). Formatting only: every number and sentence comes from the model,
  # so the two copies always agree.
  #
  # Templates live in lib/tasks/dr_report/ (outside the autoloaded tree, so the directory does
  # not become a Ruby namespace).
  module ReportRender
    TEMPLATES = Pathname.new(__dir__).join("..", "tasks", "dr_report")

    # The binding a template renders in: the model plus small formatting helpers
    class View
      ICONS = { ok: "i-ok", warn: "i-warn", fail: "i-fail" }.freeze
      EMOJI = { ok: "✅", warn: "⚠️", fail: "❌" }.freeze

      attr_reader :m

      def initialize(model)
        @m = model
      end

      def sections
        ReportModel::SECTIONS
      end

      # HTML-escape anything that may have come from the run's output (transcript text)
      def h(text)
        ERB::Util.html_escape(text.to_s)
      end

      # An inline icon for a status; the <symbol> sprite is in the template
      def icon(status)
        %(<svg class="i #{status}"><use href="##{ICONS.fetch(status, 'i-warn')}"/></svg>)
      end

      def emoji(status)
        EMOJI.fetch(status, "⚠️")
      end

      def status_word(status)
        { ok: "ok", warn: "warning", fail: "failed" }.fetch(status, "")
      end

      # Markdown table cell: a pipe or newline would break the table
      def md(text)
        text.to_s.gsub("|", "\\|").gsub(/\s*\n\s*/, " ")
      end

      def promises_source
        ReportCatalog::PROMISES[:source]
      end

      # "1 check, seen on both servers" / "2 checks" / "1 step and 1 check"
      def attention_count
        n = m.attention.size
        return "Nothing" if n.zero?

        "#{n} item#{'s' unless n == 1}"
      end

      def render(template)
        ERB.new(TEMPLATES.join(template).read, trim_mode: "-").result(binding)
      end
    end

    module_function

    def html(model)
      View.new(model).render("report.html.erb")
    end

    def markdown(model)
      View.new(model).render("report.md.erb")
    end
  end
end
