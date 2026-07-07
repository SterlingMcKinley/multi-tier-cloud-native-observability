FROM grafana/grafana:11.0.0

COPY ecs-provisioning /etc/grafana/provisioning
COPY dashboards /var/lib/grafana/dashboards

ENV GF_SECURITY_ADMIN_PASSWORD=admin \
    GF_SERVER_HTTP_ADDR=0.0.0.0

EXPOSE 3000
