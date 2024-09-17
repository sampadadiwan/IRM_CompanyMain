# How to run the observability stack

1. docker network create grafana-prometheus
2. docker run --rm --name my-prometheus --network grafana-prometheus --network-alias prometheus \
  --publish 9090:9090 --volume `my_app_dir`/config/initializers/prometheus.yml:/etc/prometheus/prometheus.yml \
  --detach prom/prometheus
3. docker run --rm --name grafana --network grafana-prometheus --network-alias grafana --publish 8000:3000 --detach grafana/grafana-oss:latest
4. Got to http://localhost:8000, login admin/admin, and import the rails.dashboard.json
5. Ensure Grafana has prometheus as the datasource, set the prometheus url to http://prometheus:9090
6. bundle exec prometheus_exporter -b 0.0.0.0 
7. Access the app and jobs, you should see metrics populating in the dashboard in grafana