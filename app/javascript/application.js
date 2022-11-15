// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "trix"
import "@rails/actiontext"
import "controllers"
import "@popperjs/core"
import "chartkick"
import '@client-side-validations/client-side-validations/src'
import "@nathanvda/cocoon"

// import "Chart.bundle"
import Highcharts from "highcharts"
window.Highcharts = Highcharts

Highcharts.setOptions({
	lang: {
  	thousandsSep: ','
  }
});

// https://github.com/basecamp/trix/issues/624
addEventListener("trix-initialize", event => {
  const { toolbarElement } = event.target;
  const inputElement = toolbarElement.querySelector("input[name=href]");
  inputElement.type = "text";
  inputElement.pattern = "(https?://|/).+";
});


$(document).on('turbo:before-cache', function() {     
  if( $('.select2-container').length > 0 ){
    // Hack to make sure select2 does not get duplicated due to turbolinks
    $('#investor_investor_entity_id').select2('destroy');
    $('#investment_investor_id').select2('destroy');
    $('#deal_investor_investor_id').select2('destroy');
    $('#folder_parent_folder_id').select2('destroy');
    $('#document_folder_id').select2('destroy');    
    $('#access_right_access_to_category').select2('destroy');    
    $('#access_right_access_to_investor_id').select2('destroy');    

  }
});

$( document ).on('turbo:load', function() {

    if (document.location.hostname.search("localhost") !== 0) {
      console.log("Google Analytics Enabled");
      window.dataLayer = window.dataLayer || [];
      function gtag(){dataLayer.push(arguments);}
      gtag('js', new Date());
      gtag('config', 'G-4CPQNX69HM');
    }

    $('[data-toggle="tooltip"]').tooltip({'placement': 'top'});
    $('.toast').toast('show');

    $('.select2').select2();
    

    "use strict"; 
    
    // Toggle the side navigation
    $("#sidebarToggle, #sidebarToggleTop").on('click', function(e) {
      $("body").toggleClass("sidebar-toggled");
      $(".sidebar").toggleClass("toggled");
      if ($(".sidebar").hasClass("toggled")) {
        $('.sidebar .collapse').collapse('hide');
      };
    });
  
    // Close any open menu accordions when window is resized below 768px
    $(window).resize(function() {
      if ($(window).width() < 768) {
        $('.sidebar .collapse').collapse('hide');
      };
      
      // Toggle the side navigation when window is resized below 480px
      if ($(window).width() < 480 && !$(".sidebar").hasClass("toggled")) {
        $("body").addClass("sidebar-toggled");
        $(".sidebar").addClass("toggled");
        $('.sidebar .collapse').collapse('hide');
      };
    });
  
    // Prevent the content wrapper from scrolling when the fixed side navigation hovered over
    $('body.fixed-nav .sidebar').on('mousewheel DOMMouseScroll wheel', function(e) {
      if ($(window).width() > 768) {
        var e0 = e.originalEvent,
          delta = e0.wheelDelta || -e0.detail;
        this.scrollTop += (delta < 0 ? 1 : -1) * 30;
        e.preventDefault();
      }
    });
  
    // Scroll to top button appear
    $(document).on('scroll', function() {
      var scrollDistance = $(this).scrollTop();
      if (scrollDistance > 100) {
        $('.scroll-to-top').fadeIn();
      } else {
        $('.scroll-to-top').fadeOut();
      }
    });
  
    // Smooth scrolling using jQuery easing
    $(document).on('click', 'a.scroll-to-top', function(e) {
      var $anchor = $(this);
      $('html, body').stop().animate({
        scrollTop: ($($anchor.attr('href')).offset().top)
      }, 1000, 'easeInOutExpo');
      e.preventDefault();
    });

    
    
});
