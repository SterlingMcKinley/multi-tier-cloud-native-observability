# Cloud-Native Observability Stack (Prometheus & Grafana)

This project provides a complete, containerized observability stack—featuring Prometheus metrics, Grafana dashboards, and Docker Compose orchestration—to demonstrate modern APM and infrastructure monitoring practices.

## This Project Features:

- **Application Instrumentation:** A custom Python application instrumented to expose standard RED (Rate, Errors, Duration) metrics.
- **Observability as Code:** Automated Grafana provisioning for data sources and dashboards—zero manual UI setup required upon deployment.
- **Infrastructure Monitoring:** Real-time host metrics captured via Prometheus Node Exporter.
- **Isolated Network Architecture:** Containerized microservices running on a dedicated bridge network to ensure secure, internal metrics scraping.

## Tech Stack

LOCAL ENVIRONMENT

- **Monitoring:** Prometheus, Node Exporter
- **Visualization:** Grafana
- **Application:** Python, Flask, Prometheus Client Library
- **Orchestration:** Docker, Docker Compose

AWS ENVIRONMENT

- **Monitoring:** Prometheus
- **Visualization**: Grafana
- **Application**: Python, Flask, Prometheus Client Library
- **Orchestration**: Amazon ECS, AWS Fargate, ECR (Registry), Docker
- **Networking & Security**: AWS VPC, Security Groups, AWS IAM

## Architecture Diagram

LOCAL ENVIRONMENT
<img width="2528" height="1310" alt="diagram" src="https://github.com/user-attachments/assets/04a58aa5-8050-4752-a1e5-4f816eec578e"/>

AWS ENVIRONMENT
_PENDING_

## Steps: (Local Environment)

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

## ECS / ECR Deployment Steps (AWS Environment)

Instead of executing manual AWS CLI commands for task registrations and service creations, the entire workflow was handled by a single orchestrator script. HEre are steps to deploy the local Obserability Stack to AWS environment.

- 1. Run the Deployment Script:
     Execute the automation script to build images, push to ECR, configure networking/security groups, and launch the service:

```
./scripts/deploy-ecs-stack.sh
```

This script automates the full ECS deployment of the observability stack. It builds and pushes the web app, Prometheus, and Grafana container images to ECR, creates the ECS execution role, registers a task definition, discovers networking details from the default VPC, opens the needed ports in the security group, and creates or updates an ECS service on Fargate so the stack runs in AWS.

- 2. Verify the Deployment:
     Monitor the script output as it automatically registers the ECS task definition, checks for the ECS execution role, and creates or updates the Fargate ECS service.

- 3. Open Grafana UI at http://<PUBLIC_IP>:3000 (Login: admin / admin).

- 4. Validate Dashboards:
     Once the script confirms the ECS service is healthy, open Grafana UI at http://<PUBLIC_IP>:3000 (Login: admin / admin) (dynamically configured public URL) and verify that the Prometheus data source is connected.

- 5. Create a dashboard and add panels using the following PromQL queries:
     - Total Requests: sum(rate(app_requests_total[1m]))
     - Error Rate (500s): sum(rate(app_requests_total{http_status="500"}[1m]))
     - Latency (95th Percentile): histogram_quantile(0.95, sum(rate(app_request_latency_seconds_bucket[5m])) by (le))

- 6. Traffic Generation:
     Generate synthetic traffic by hitting the deployed Web App service endpoint to verify that live metrics are populating the Grafana dashboards.

## Dashboards - AWS Production environment

_PENDING_

<img width="1905" height="1016" alt="aws_dashboard" src="https://github.com/user-attachments/assets/1eca8825-b27a-4543-b8f7-ed45833d011f" />


<img width="1912" height="542" alt="aws_ecr" src="https://github.com/user-attachments/assets/be46bcac-21b9-41fa-8315-1e01ed6ace71" />


<img width="1872" height="485" alt="aws_ecs" src="https://github.com/user-attachments/assets/9ec2578c-f904-469e-8dbb-d17a78d046e2" />


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

---

### Local Deployment vs AWS ECS Deployment: Configuration Compatibility

- **Issue:** The local Docker Compose deployment worked because configuration files were mounted from the host environment and service discovery used container names such as `prometheus` and `grafana`. When moving to AWS ECS, those same assumptions no longer held, and the containers needed to be packaged with their own configuration and defined explicitly through ECS task and service definitions.

- **Solution:** I adapted the stack for AWS by building custom Prometheus and Grafana images with the required provisioning files baked in, updating the datasource configuration to use ECS-friendly networking, and defining the deployment through ECS task and service definitions so the stack could run reliably on Fargate.

---

### Prometheus Port Exposure and Grafana Data Flow

- **Issue:** When the services were moved to ECS, Prometheus was not exposed to the expected network path and Grafana could not reliably discover or scrape the application metrics endpoint. This caused the observability flow to break even though the containers were running.

- **Solution:** I updated the deployment to explicitly allow ingress on the application and Prometheus ports, verified the container networking path, and ensured Grafana’s datasource configuration pointed to the correct ECS-accessible endpoint. I provisioned ingress routing infrastructure using the AWS CLI to authorize ingress TCP traffic on ports 5000 and 9090 from defined CIDR blocks (0.0.0.0/0 for initial validation), opening the perimeter gateway for metrics auditing and dashboard integration.

---

### Prometheus Metrics Not Found

- **Issue:** During the initial dashboard setup, the query sum(rate(app_requests_total[1m])) returned no data (empty charts), or there was confusion regarding whether to use the application-specific metric versus the internal platform metric prometheus_http_requests_total.

- **Solution PENDING** Issue still currently pending which is why a couple panels are blank. I am researching a solution. So far my research has discovered:
  - 1- app_requests_total (Application Layer): This is a custom metric explicitly instrumented inside our Python Flask application source code to track real user/client traffic hitting endpoints like / and /error. Prometheus_http_requests_total (Platform/Control Plane Layer): This is a native, built-in metric generated automatically by the Prometheus server engine itself. It has zero awareness of the Python application.
  - 2-that Prometheus metrics like rate() and histogram_quantile() require a continuous stream of data over time to calculate averages. I started the containers and haven't visited th application web pages yet, there is literally no data in the time window ([1m] or [5m]) to calculate. Because there are no data points, the math returns an empty set.
