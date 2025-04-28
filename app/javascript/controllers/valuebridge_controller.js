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

    Highcharts.chart(chartElement.id, { // ← use dynamic id
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

    console.log("Waterfall chart initialized for", chartElement.id);
  }
}
