import Highcharts from "highcharts"
import "highcharts-more"
import "highcharts/modules/exporting"
import "highcharts/modules/offline-exporting"

// Make Highcharts globally available for Chartkick and other scripts
window.Highcharts = Highcharts

// Global Highcharts configuration
Highcharts.setOptions({
  lang: {
    thousandsSep: ',',
    decimalPoint: '.'
  }
});

/**
 * Global handler for chart clicks to enable interactive filtering.
 * Updates the URL with Ransack parameters and refreshes the target Turbo Frame.
 * 
 * @param {string} param - The Ransack query parameter (e.g., 'q[category_eq]')
 * @param {string} value - The value from the clicked chart point
 * @param {string} frameId - The ID of the Turbo Frame to refresh
 */
window.handleChartClick = function(param, value, frameId) {
  // Ignore clicks on aggregated "Others" slices
  if (value === "Others") return;

  const url = new URL(window.location.href);
  
  // Map human-readable chart labels to database-friendly boolean strings
  let filterValue = value;
  if (value === "Verified" || value === "Completed") filterValue = "true";
  if (value === "Unverified" || value === "Pending") filterValue = "false";

  // Append or update the Ransack filter in the URL
  url.searchParams.set(param, filterValue);
  
  // Update the target Turbo Frame to reflect the new filters
  const frame = document.getElementById(frameId);
  if (frame) {
    frame.src = url.toString();
    // Update browser history so filters persist on page refresh
    window.history.pushState({}, "", url.toString());
  } else {
    // Fallback to full page visit if frame is not found
    window.Turbo.visit(url.toString());
  }
};

/**
 * Global Highcharts event listener.
 * Intercepts point clicks and triggers handleChartClick if the series is marked as 'clickable'.
 */
Highcharts.addEvent(Highcharts.Point, 'click', function () {
  const seriesOptions = this.series.options;
  
  // Only process clicks for charts explicitly configured with clickable: true
  if (seriesOptions.clickable) {
    // Determine the correct value based on chart type
    // Pie charts use 'name', Cartesian charts (Column/Area) use 'category'
    const value = (this.series.type === 'pie') ? this.name : (this.category || this.name);
    window.handleChartClick(seriesOptions.clickParam, value, seriesOptions.clickFrameId);
  }
});
