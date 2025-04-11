import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    let chartElement = $("#waterfall-chart");
    let chartData = chartElement.data("chart-values");

    console.log("Raw Data Attribute:", chartData); // Debugging Step

    try {
      chartData = JSON.parse(chartData);
    } catch (e) {
      console.error("Invalid JSON Data for Chart:", e);
      return;
    }

    Highcharts.chart("waterfall-chart", {
      chart: { type: 'waterfall' },
      title: { text: '' },
      xAxis: { type: 'category' },
      yAxis: { title: { text: 'Amount' } },
      series: [{
        name: "Value Bridge",
        data: chartData,
        dataLabels: { enabled: true }
      }]
    });

    console.log("Waterfall chart initialized");
  }
}
