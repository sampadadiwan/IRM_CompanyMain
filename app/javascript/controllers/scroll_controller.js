import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  connect() {
    console.log("scroll controller connected");
    $("#chat-msg-list").on("DOMNodeInserted", this.resetScroll); 
    this.resetScroll()
  }

  resetScroll() {
    $("#chat-msg-list").scrollTop($("#chat-msg-list")[0].scrollHeight - $("#chat-msg-list")[0].clientHeight);
  }
}
