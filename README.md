# Cloud-Native Observability Stack (Prometheus & Grafana)

This project production-ready blueprint demonstrating containerized application performance monitoring (APM) and infrastructure observability using Prometheus, Grafana, and Docker Compose.

## Features

- **Application Instrumentation:** A custom Python application instrumented to expose standard RED (Rate, Errors, Duration) metrics.
- **Observability as Code:** Automated Grafana provisioning for data sources and dashboards—zero manual UI setup required upon deployment.
- **Infrastructure Monitoring:** Real-time host metrics captured via Prometheus Node Exporter.
- **Isolated Network Architecture:** Containerized microservices running on a dedicated bridge network to ensure secure, internal metrics scraping.

## Tech Stack

- **Monitoring:** Prometheus, Node Exporter
- **Visualization:** Grafana
- **Application:** Python, Flask, Prometheus Client Library
- **Orchestration:** Docker, Docker Compose

## Architecture Diagram& Directory Structure

prometheus-grafana-portfolio/
├── README.md
├── docker-compose.yml
├── app/
│ ├── Main.py
│ └── Requirements.txt
├── prometheus/
│ └── prometheus.yml
└── grafana/
├── provisioning/
│ ├── datasources/
│ │ └── datasource.yml
│ └── dashboards/
│ └── dashboards.yml
└── dashboards/
└── app_dashboard.json

## Dashboards

### Issues/Lessons Learned:
