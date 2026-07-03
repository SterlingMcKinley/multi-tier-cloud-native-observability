# Cloud-Native Observability Stack (Prometheus & Grafana)

This project provides a complete, containerized observability stack—featuring Prometheus metrics, Grafana dashboards, and Docker Compose orchestration—to demonstrate modern APM and infrastructure monitoring practices.

## This Project Features:

- **Application Instrumentation:** A custom Python application instrumented to expose standard RED (Rate, Errors, Duration) metrics.
- **Observability as Code:** Automated Grafana provisioning for data sources and dashboards—zero manual UI setup required upon deployment.
- **Infrastructure Monitoring:** Real-time host metrics captured via Prometheus Node Exporter.
- **Isolated Network Architecture:** Containerized microservices running on a dedicated bridge network to ensure secure, internal metrics scraping.

## Tech Stack

- **Monitoring:** Prometheus, Node Exporter
- **Visualization:** Grafana
- **Application:** Python, Flask, Prometheus Client Library
- **Orchestration:** Docker, Docker Compose

## Architecture Diagram

<img width="2528" height="1310" alt="diagram" src="https://github.com/user-attachments/assets/04a58aa5-8050-4752-a1e5-4f816eec578e"/>

## Steps:

- Developed an instrumented Python application that generates metrics.
  - I made sure to define Prometheus metrics (Count, Latency)
  - Configured Prometheus & Node Exporter
- Created YAML files to automate Grafana Provisioning.
  - [Observability As Code] Instead of manually clicking "Add Data Source" in Grafana, I used provisioning files so the project launches fully configured.
- Orchestrate with Docker Compose
  - The docker-compose.yml file defines a complete observability stack including my own Python web app, all running together on a shared Docker network.
  - web-app — Python application
  - prometheus — metrics scraper (image: prom/prometheus:latest)
  - node-exporter — host-level metrics collector (image: prom/node-exporter:latest)
  - grafana — dashboards + visualization (image: grafana/grafana:latest)
- Build, Run, & Design
  1. Run command: docker-compose up --build -d
  2. Generate some synthetic traffic by using http://localhost:5000/ and http://localhost:5000/error multiple times.
  3. Open Grafana UI at http://localhost:3000 (Login: admin / admin).
  4. Go to Dashboards -> Create Dashboard. Add panels using the PromQL metrics that I built:
  - Total Requests: sum(rate(app_requests_total[1m]))
  - Error Rate (500s): sum(rate(app_requests_total{http_status="500"}[1m]))
  - Latency (95th Percentile): histogram_quantile(0.95, sum(rate(app_request_latency_seconds_bucket[5m])) by (le))
  5. Click the "Share" icon at the top of the dashboard -> Export -> Save as JSON. Saved this file to my local grafana/dashboards/app_dashboard.json folder so it version-controls perfectly.

## Dashboards

<img width="1563" height="499" alt="Dashboard" src="https://github.com/user-attachments/assets/d60bc50f-0b97-4947-a529-262adb00ac69" />
<img width="1575" height="719" alt="generate_traffic3" src="https://github.com/user-attachments/assets/699812d1-ef6f-4770-9f9f-714f061f3676" />

## Issues / Lessons Learned

### Configuration Drift: Docker-Compose Schema Compatibility

- **Issue:** Initial deployment of the containerized Python application via `docker-compose` failed during the orchestration phase. The runtime daemon threw a compatibility regression error due to a mismatch between the engine's parser capabilities and the declared file schema version.

  `ERROR: Version in "./docker-compose.yml" is unsupported. `

- **Solution:** Two remediation paths were identified:
  1. Demote the schema definition from `version: '3.8'` to `version: '3.3'` to match the legacy host environment.
  2. Omit the `version` attribute entirely, allowing the modern Compose V2 specification to default to standard evaluation.

  **Solution:** Opted for backward compatibility by pinning the schema definition to version `3.3`.

---

### Observability Pipeline Validation: Synthetic Traffic Generation

- **Issue:** In my local development environment, the lack of organic ingress traffic resulted in a data starvation issue on the Prometheus/Grafana observability stack, preventing the validation of alerting thresholds, SLIs, and dashboard visualizations.

- **Solution:** Implemented concurrent synthetic load generation scripts to mock real-world user behavior, simulating both nominal operations and upstream service failures to populate metrics.

**Remediation Scripts:**

_*High-throughput baseline traffic (HTTP 200 OK simulation):*_

  ```bash
  while true; do curl -s http://localhost:5000 > /dev/null & done
  ```


  <img width="822" height="281" alt="successful_200" src="https://github.com/user-attachments/assets/59aa3933-e0ed-4dc8-bf68-282b14e73a54" /><br>
  

_*Fault injection baseline traffic (HTTP 500 Internal Server Error simulation):*_

```bash
while true; do curl -s http://localhost:5000/error > /dev/null & done
```

<img width="822" height="281" alt="error_500" src="https://github.com/user-attachments/assets/a25dd64d-b193-4f12-b811-f0632bbecefb" />

