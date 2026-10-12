// Import and register all your controllers from the importmap under controllers/*

import { application } from "controllers/application"

// Lazy load controllers as they appear in the DOM: a page imports only the controllers its
// data-controller attributes name, and a MutationObserver picks up ones added later (Turbo
// frames/streams, modals, cocoon rows). Eager loading imported all ~200 controllers - and the
// libraries they pull in - on every full page load. The import map pins controllers with
// preload: false (config/importmap.rb) so the browser doesn't fetch them all anyway.
// Consequence for controller code: another controller on the page may not be loaded yet when
// yours connects, so treat getControllerForElementAndIdentifier(...) as possibly null.
import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"
lazyLoadControllersFrom("controllers", application)

//This is required to ensure that forms loaded via turbo have the ClientSideValidations turned on.
document.documentElement.addEventListener('turbo:frame-load', function (e) {
    // console.log($(e.target).find('form'));
    if($(e.target).find('form').length > 0) {
        $(e.target).find('form').enableClientSideValidations();
    }
});

// app/javascript/application.js
// addEventListener("turbo:before-frame-render", (event) => {
//     if (document.startViewTransition) {
//       const originalRender = event.detail.render
//       event.detail.render = (currentElement, newElement) => {
//         document.startViewTransition(()=> originalRender(currentElement, newElement))
//       }
//     }
// })

