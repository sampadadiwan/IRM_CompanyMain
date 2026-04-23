import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["chart"]

  connect() {
    this.chartTarget.dataset.chartValues && this.initializeChart();
  }

  resolveClassColor(cssClass, fallback) {
    const el = document.createElement('span');
    el.className = cssClass;
    el.style.display = 'none';
    document.body.appendChild(el);
    const color = getComputedStyle(el).color || fallback;
    document.body.removeChild(el);
    return color;
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
    const positiveColor = this.resolveClassColor('value-bridge-positive', '#00565C');
    const negativeColor = this.resolveClassColor('value-bridge-negative', '#B21832');

    const pointWidth = chartElement.dataset.pointWidth ? parseInt(chartElement.dataset.pointWidth) : null;

    Highcharts.chart(chartElement.id, { // ← use dynamic id
      chart: { type: 'waterfall', ...(themeOptions.chart || {}) },
      title: { text: '' },
      xAxis: { type: 'category', ...(themeOptions.xAxis || {}) },
      yAxis: { title: { text: null }, labels: { enabled: false }, ...(themeOptions.yAxis || {}) },
      legend: { enabled: false },
      series: [{
        name: "Value Bridge",
        data: chartData,
        pointWidth: pointWidth,
        upColor: null, // Allow individual point colors for positive values
        dataLabels: {
          enabled: true,
          inside: true,
          overflow: 'allow',
          crop: false,
          backgroundColor: 'transparent',
          borderWidth: 0,
          formatter: function() {
            const label = this.point.options.label || this.y;
            return `<span>${label}</span>`;
          },
          useHTML: true,
          style: {
            textOutline: '1px #000000',
            color: '#ffffff',
            fontWeight: 'bold',
            fontSize: '13px'
          }
      }
      }]
    });

    console.log("Waterfall chart initialized for", chartElement.id);
  }

  submit() {
    this.element.closest("form").requestSubmit();
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
          labels: { style: { color: 'white', fontSize: '13px' } }
        },
        yAxis: {
          gridLineWidth: 0.2,
          gridLineColor: "#7c8fac",
          labels: { style: { color: 'white', fontSize: '13px' } }
        },
        labelColor: 'white'
      };
    } else {
      return {
        labelColor: 'black',
        xAxis: { labels: { style: { fontSize: '13px' } } }
      };
    }
  }
}
