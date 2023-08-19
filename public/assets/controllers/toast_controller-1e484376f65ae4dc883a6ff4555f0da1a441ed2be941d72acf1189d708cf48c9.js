import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    $('.toast').toast('show');
  }
};
