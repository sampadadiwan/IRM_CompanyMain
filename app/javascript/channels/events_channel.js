import consumer from "channels/consumer"

consumer.subscriptions.create("EventsChannel", {
  connected() {
    // Called when the subscription is ready for use on the server
    console.log("Hello WS");
  },

  disconnected() {
    // Called when the subscription has been terminated by the server
  },

  received(data) {
    const url = window.location.href;
    if(url.includes(data["item"]) && url.includes(data["item_id"])) {
      console.log("Recieved");
      $(".search-button").eq(0).click();
      $(".btn.btn-outline-primary.show_details_link").click();
    }
  }
});
