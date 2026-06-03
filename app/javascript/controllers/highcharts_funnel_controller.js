import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    data: Array,
    title: String,
    theme: Object
  }

  connect() {
    // Highcharts + funnel module are loaded via importmap in charts_handler.js,
    // so window.Highcharts is always available by the time this controller connects.
    this.renderChart()
  }

  renderChart() {
    // Guard: if all-zero data slipped through, don't render a broken chart
    const data = this.dataValue
    if (!data || data.length === 0 || data.every(point => point[1] === 0)) return

    const colors = ['#5D87FF', '#39B69A', '#FFAE1F', '#FA896B', '#00A5FF', '#7C8FAC', '#536BBD']

    Highcharts.chart(this.element, {
      chart: {
        type: 'funnel',
        backgroundColor: 'transparent',
        spacingRight: 150,
        spacingLeft: 20,
        spacingTop: 20,
        spacingBottom: 20
      },
      title: {
        text: ''
      },
      colors: colors,
      credits: {
        enabled: false
      },
      series: [{
        name: 'Investors',
        data: data,
        center: ['40%', '50%'],
        width: '60%',
        neckWidth: '25%',
        neckHeight: '20%',
        dataLabels: {
          enabled: true,
          useHTML: true,
          format: '<div style="text-align: left;"><span style="color:#5A6A85; font-weight: 600; font-size: 11px;">{point.name}</span><br/><span style="color:#2A3547; font-size: 14px; font-weight: 700;">{point.y}</span></div>',
          softConnector: true,
          connectorColor: '#ebf1f6',
          connectorWidth: 1,
          distance: 40,
          style: {
            textOutline: 'none'
          }
        }
      }],
      tooltip: {
        headerFormat: '',
        pointFormat: '<span style="color:{point.color}">●</span> <b>{point.name}</b>: {point.y} Investors',
        backgroundColor: '#ffffff',
        borderColor: '#ebf1f6',
        borderRadius: 8,
        shadow: true,
        style: {
          color: '#2A3547',
          fontSize: '12px'
        }
      },
      plotOptions: {
        series: {
          borderWidth: 2,
          borderColor: '#ffffff',
          shadow: false,
          states: {
            hover: {
              brightness: 0.1,
              borderWidth: 3
            }
          }
        }
      }
    })
  }
}
