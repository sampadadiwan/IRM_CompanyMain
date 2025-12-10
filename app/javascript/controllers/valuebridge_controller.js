import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["chart"]

  connect() {
    this.chartTarget.dataset.chartValues && this.initializeChart();
  }

  initializeChart() {
    let chartElement = this.chartTarget;
    let chartData = chartElement.dataset.chartValues;

    console.log("Raw Data Attribute:", chartData);

    try {
      chartData = JSON.parse(chartData);
    } catch (e) {
      console.error("Invalid JSON Data for Chart:", e);
      return;
    }

    const themeOptions = this.getThemeOptions();

    Highcharts.chart(chartElement.id, { // ← use dynamic id
      chart: { type: 'waterfall', ...(themeOptions.chart || {}) },
      title: { text: '' },
      xAxis: { type: 'category', ...(themeOptions.xAxis || {}) },
      yAxis: { title: { text: 'Amount' }, ...(themeOptions.yAxis || {}) },
      series: [{
        name: "Value Bridge",
        data: chartData,
        dataLabels: {
          enabled: true,
          inside: true,
          backgroundColor: 'transparent', // removes white background
          borderWidth: 0,                 // remove border if any
          style: {
            textOutline: 'none',          // removes white halo
            color: themeOptions.labelColor || '#ffffffff', // set text color manually if needed
            fontWeight: 'bold'
          }
      }
      }]
    });

    console.log("Waterfall chart initialized for", chartElement.id);
  }

  getThemeOptions() {
    let adminSettings = {};
    const nameEQ = "adminSettings=";
    const ca = document.cookie.split(';');
    for(let i=0;i < ca.length;i++) {
        let c = ca[i];
        while (c.charAt(0)==' ') c = c.substring(1,c.length);
        if (c.indexOf(nameEQ) == 0) {
            try {
                adminSettings = JSON.parse(c.substring(nameEQ.length,c.length));
            } catch(e) {}
            break;
        }
    }

    if (adminSettings["Theme"] === "dark") {
      return {
        chart: { backgroundColor: "#2a3447" },
        xAxis: {
          lineColor: "#7c8fac",
          gridLineColor: "#7c8fac",
          labels: { style: { color: 'white' } }
        },
        yAxis: {
          gridLineWidth: 0.2,
          gridLineColor: "#7c8fac",
          labels: { style: { color: 'white' } }
        },
        labelColor: 'white'
      };
    } else {
      return { labelColor: 'black' };
    }
  }
}
