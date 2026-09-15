import { Controller } from "@hotwired/stimulus"

// Enhances the tasks filter bar (tasks/_filter_bar.html.erb), shared by the
// tasks list and the kanban board.
//
// The bar works without this controller: each select calls form.requestSubmit(),
// and the form carries data-turbo-frame="_top", so a filter always at minimum
// navigates to the filtered list. If this controller fails to register, or bails
// out below, the filter still applies. It must never be the reason a select does
// nothing.
//
// What it adds: inside an embedded tab the list is loaded into a turbo frame the
// host page named, and there a full navigation would throw the user off the
// record they are looking at. So it cancels the submit and navigates just that
// frame, by assigning its src and letting Turbo render the response.
export default class extends Controller {
  static values = { frame: String }

  submit(event) {
    const id = this.frameValue

    // "_top" is the standalone /tasks page: a full navigation is wanted there so
    // the stat cards, which sit outside every frame and read the same filters,
    // are recomputed with the list. Returning without preventDefault lets the
    // form's own submit carry it out.
    if (!id || id === "_top") return

    const frame = this.targetFrame(id)
    if (!frame) {
      console.warn(`task-filter: no <turbo-frame id="${id}"> on the page, letting the form submit`)
      return
    }

    event.preventDefault()

    const url = this.filteredUrl()

    // These frames are declared loading="lazy", and Turbo only acts on a src
    // change when the loading style is eager or its private #hasBeenLoaded flag
    // is set - a flag that is false on a frame element re-created rather than
    // loaded by Turbo, which is what custom/turbo_handler.js does when it swaps
    // a frame's innerHTML for pagination. Eager is correct by now in any case:
    // the tab is open and on screen, so there is nothing left to defer.
    frame.setAttribute("loading", "eager")

    // Assigning src is what makes the frame fetch and re-render. When the URL is
    // unchanged (re-picking a value that is already applied) the attribute never
    // changes and nothing would fire, so reload() re-issues it.
    if (frame.getAttribute("src") === url) {
      frame.reload()
    } else {
      frame.src = url
    }
  }

  // The frame to refresh, resolved as an ancestor of this form FIRST.
  //
  // getElementById is the wrong tool when ids are not unique, and on these pages
  // they have not always been: a deal investor page rendered turbo_frame_tag
  // "tasks_frame" twice, so every lookup - Turbo's own frame targeting included
  // - resolved to whichever came first in the document, an unrelated tab's frame
  // that had never been shown. Fetching and rendering then worked perfectly and
  // updated something nobody was looking at.
  //
  // The frame wrapping this form is by definition the one whose list the user is
  // filtering, so walk up to it and let a stray duplicate elsewhere on the page
  // be somebody else's problem. closest() matches through the nested frame too:
  // on a deal tab the form sits in "task_list" inside the "tasks_frame" it names.
  targetFrame(id) {
    return this.element.closest(`turbo-frame#${CSS.escape(id)}`) || document.getElementById(id)
  }

  // A GET form's fields become the query string, replacing whatever the action
  // carried - the same thing the browser does natively. FormData keeps repeated
  // names (owner_type_in[], say) as repeated params.
  filteredUrl() {
    const url = new URL(this.element.action, window.location.href)
    url.search = new URLSearchParams(new FormData(this.element)).toString()
    return url.toString()
  }
}
