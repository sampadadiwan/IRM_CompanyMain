# Waits for the page's Stimulus controllers to connect (and for any Bootstrap modal around the
# element to finish animating) before a test interacts with it.
#
# Controllers are lazy-loaded (app/javascript/controllers/index.js): after a page loads, the loader
# scans it, imports each named controller's module, and only then connects it. A step that acts in
# that window acts on bare markup - e.g. set_custom_field types a date and fires `input`, but the
# locale-date controller that copies it into the hidden ISO field isn't listening yet, so the form
# submits without the date (form_custom_field_validations.feature:183). Real users don't act within
# a few hundred ms of a page load; tests do, on every step.
#
# So before every visit returns and before every click/fill/select, wait (up to STIMULUS_READY_WAIT)
# until each controller named in the page's data-controller attributes is connected. Names with no
# controller file never connect, so only names the import map knows are counted. Once the page has
# settled the check is a single evaluate returning true.
module StimulusReady
  STIMULUS_READY_WAIT = 5 # seconds

  ALL_CONNECTED_JS = <<~JS.freeze
    (() => {
      const app = window.Stimulus;
      if (!app) return true;  // no Stimulus on this page (about:blank, plain HTML responses)
      const map = document.querySelector('script[type="importmap"]');
      const imports = map ? (JSON.parse(map.textContent).imports || {}) : {};
      // Same identifier -> module mapping the lazy loader uses (stimulus-loading)
      const known = id => `controllers/${id.replace(/--/g, "/").replace(/-/g, "_")}_controller` in imports;
      return Array.from(document.querySelectorAll("[data-controller]")).every(el =>
        el.getAttribute("data-controller").split(/\\s+/).filter(Boolean).filter(known)
          .every(id => app.getControllerForElementAndIdentifier(el, id))
      );
    })()
  JS

  def self.wait(playwright_page)
    url = playwright_page.url rescue nil
    # A page that already timed out (a controller that never connects, e.g. it threw on import)
    # would otherwise cost the full wait on every later click/fill on it
    return if url && url == @timed_out_url

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + STIMULUS_READY_WAIT
    loop do
      # A navigation mid-check destroys the context; the next interaction checks again
      ready = begin
        playwright_page.evaluate(ALL_CONNECTED_JS)
      rescue StandardError
        true
      end
      return if ready

      # Never fail the step from here: a controller that can't connect is the step's own problem
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        @timed_out_url = url
        warn "StimulusReady: controllers still connecting after #{STIMULUS_READY_WAIT}s on #{url}"
        return
      end

      sleep 0.05
    end
  end

  # True unless the element sits in a Bootstrap modal that is still animating open or closed.
  # Bootstrap moves focus onto the modal when the open transition ENDS (focustrap); under load that
  # lands mid-fill. The driver fills all but the last character and then types it as a keypress, so the
  # last key went to the modal instead: "01/01/202" stayed in the date input, locale-date cleared the
  # hidden ISO field for the partial date, and the form submitted no date at all
  # (allocation_run_templates.feature:200 - "No valid period given", parallel runs only).
  MODAL_SETTLED_JS = <<~JS.freeze
    el => {
      const modal = el.closest(".modal");
      const instance = modal && window.bootstrap && window.bootstrap.Modal.getInstance(modal);
      return !(instance && instance._isTransitioning);
    }
  JS
  MODAL_SETTLE_WAIT = 3 # seconds; a fade is ~0.3 s unloaded

  def self.wait_for_modal(element)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + MODAL_SETTLE_WAIT
    until (element.evaluate(MODAL_SETTLED_JS) rescue true)
      return if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.05
    end
  end

  # Capybara::Playwright::Node - the page is @page, the element @element
  module NodeInteractions
    %i[set click double_click right_click select_option unselect_option send_keys].each do |name|
      define_method(name) do |*args, **opts, &blk|
        StimulusReady.wait(@page)
        StimulusReady.wait_for_modal(@element)
        super(*args, **opts, &blk)
      end
    end
  end

  # Capybara::Playwright::Browser - the page is @playwright_page
  module BrowserVisit
    def visit(path)
      super.tap { StimulusReady.wait(@playwright_page) }
    end
  end
end

Capybara::Playwright::Node.prepend(StimulusReady::NodeInteractions)
Capybara::Playwright::Browser.prepend(StimulusReady::BrowserVisit)
