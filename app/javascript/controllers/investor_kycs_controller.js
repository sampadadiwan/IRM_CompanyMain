// import { Controller } from "@hotwired/stimulus"
import  ServerDatatableController from "controllers/server_datatable_controller"

export default class extends ServerDatatableController {

  kyc_type_changed(event) {
    let kyc_type = $('#kyc_type').val();
    console.log("kyc_type", kyc_type);

    let href = new URL(window.location.href);
    href.searchParams.set('kyc_type', kyc_type);
    console.log(href.toString());

    window.location.href = href.toString();
  } 
  
}
