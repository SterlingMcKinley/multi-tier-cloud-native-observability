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

## Dashboards

<img width="1563" height="499" alt="Dashboard" src="https://github.com/user-attachments/assets/d60bc50f-0b97-4947-a529-262adb00ac69" />
<img width="1575" height="719" alt="generate_traffic3" src="https://github.com/user-attachments/assets/699812d1-ef6f-4770-9f9f-714f061f3676" />

### Issues/Lessons Learned:
