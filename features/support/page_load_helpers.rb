# Waiting for a form submission or navigation that a step set off, instead of a fixed sleep.
#
# Steps that submit something and then read the database (or the URL) used to `sleep(1)` so the
# request had time to finish. The request's own completion is observable in the browser:
#   - a Turbo form submission fires `turbo:submit-end` when the server has answered;
#   - a Turbo link visit fires `turbo:load` once the new page is rendered;
#   - a native submit / full navigation replaces `window`, dropping the marker set below.
# By the time any of these happens the server has finished the request, so its writes are visible.
module PageLoadHelpers
  # Runs the block (the click / script that submits or navigates) and waits until the browser has
  # seen one of the completion signals above, up to `timeout` seconds. Never raises - it replaces
  # sleeps that never failed on their own, so a click that turns out not to submit anything simply
  # moves on after `timeout`, and the step's real assertion decides.
  # Pass the length of the sleep being replaced as `timeout`: some clicks fire none of the signals
  # (e.g. the KPI "confirm the dialog" step), and there the wait runs to its cap - a 5 s default in
  # place of a 1 s sleep made those steps slower, not faster.
  def wait_for_page_after(timeout: 5)
    # Arm the marker and listeners on the current page before acting
    begin
      page.execute_script(<<~JS)
        window.__pcucPending = true;
        const done = () => { window.__pcucPending = false; };
        document.addEventListener("turbo:submit-end", done, { once: true });
        document.addEventListener("turbo:load", done, { once: true });
      JS
    rescue Capybara::NotSupportedByDriverError
      # rack_test scenarios (e.g. the 2FA ones) have no JS, and rack_test finishes each request
      # before the click returns, so there is nothing to wait for
      return yield
    end
    yield
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      # A navigation in progress destroys the context mid-evaluate: treat as "not yet"
      finished = begin
        page.evaluate_script("window.__pcucPending !== true")
      rescue StandardError
        false
      end
      break if finished || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.05
    end
  end
end

World(PageLoadHelpers)
