// Import and register all your controllers from the importmap under controllers/*

import { application } from "controllers/application"

// Eager load all controllers defined in the import map under controllers/**/*_controller
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"
eagerLoadControllersFrom("controllers", application)

// Lazy load controllers as they appear in the DOM (remember not to preload controllers in import map!)
// import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"
// lazyLoadControllersFrom("controllers", application)

//This is required to ensure that forms loaded via turbo have the ClientSideValidations turned on. 
document.documentElement.addEventListener('turbo:frame-load', function (e) {
    console.log($(e.target).find('form'));
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
  
import "./json_formatter_controller"