# FreeIPA Monitoring with ipa-healthcheck, Prometheus, and Grafana

Companion repo for the ComputingForGeeks guide:
**[Monitoring FreeIPA with ipa-healthcheck, Prometheus, and Grafana](https://computingforgeeks.com/freeipa-healthcheck-prometheus-grafana/)**

`ipa-healthcheck` ships in the box with FreeIPA and runs 283 checks in under ten
seconds, but it dumps a wall of JSON nobody reads. This repo wires it into
Prometheus and surfaces the results in Grafana with alerts on the four signals
that actually correlate with an outage: services down, certificates expiring,
replication conflicts, and the healthcheck itself going stale.

## Contents

| File | What it is |
|---|---|
| `freeipa-dashboard.json` | The Grafana dashboard (UID `freeipa-healthcheck`, title "FreeIPA Health Overview"). Six severity stats, a per-severity time series, service-status and per-check tables, and a cert-expiry bar gauge. |
| `ipa-healthcheck-export.sh` | The exporter script. Runs on the IPA server, writes a Prometheus textfile for node_exporter. |
| `systemd/ipa-healthcheck-export.service` | Oneshot unit that runs the exporter. |
| `systemd/ipa-healthcheck-export.timer` | Fires the exporter every 5 minutes. |
| `prometheus/prometheus-scrape.yml` | Scrape config (single server + multi-replica variant). |
| `prometheus/ipa-alerts.yml` | The eight alert rules (five core + three replica/PKI extras). |

## Quick start

On the **IPA server** (node_exporter must already be installed with the
textfile collector enabled at `/var/lib/node_exporter/textfile_collector`):

```bash
sudo install -m 0755 ipa-healthcheck-export.sh /usr/local/bin/ipa-healthcheck-export.sh
sudo cp systemd/ipa-healthcheck-export.* /etc/systemd/system/
sudo systemctl enable --now ipa-healthcheck-export.timer
sudo /usr/local/bin/ipa-healthcheck-export.sh   # seed the first textfile
```

On the **monitoring host** (Prometheus + Grafana):

```bash
# Prometheus rules + scrape (merge into your prometheus.yml)
sudo cp prometheus/ipa-alerts.yml /etc/prometheus/ipa-alerts.yml
sudo -u prometheus promtool check rules /etc/prometheus/ipa-alerts.yml
curl -s -X POST http://localhost:9090/-/reload
```

### Import the Grafana dashboard

**Web UI:** Dashboards -> New -> Import -> upload `freeipa-dashboard.json`, then
pick your Prometheus data source from the dropdown.

**API** (give the data source a fixed UID so the import resolves cleanly):

```bash
GRAFANA="http://localhost:3000"
GF_AUTH="admin:admin"   # Grafana factory default, change after first login

# One-time: create the data source with an explicit uid
curl -s -u "$GF_AUTH" -X POST "$GRAFANA/api/datasources" \
  -H "Content-Type: application/json" \
  -d '{"name":"Prometheus","uid":"prometheus","type":"prometheus","access":"proxy","url":"http://localhost:9090","isDefault":true}'

# Import, mapping the dashboard's data-source input to that uid
python3 -c 'import json; print(json.dumps({"dashboard": json.load(open("freeipa-dashboard.json")), "overwrite": True, "inputs": [{"name":"DS_PROMETHEUS","type":"datasource","pluginId":"prometheus","value":"prometheus"}]}))' > /tmp/dash-import.json

curl -s -u "$GF_AUTH" -X POST "$GRAFANA/api/dashboards/import" \
  -H "Content-Type: application/json" \
  --data @/tmp/dash-import.json
```

Browse to `/d/freeipa-healthcheck/freeipa-health-overview` to confirm it rendered.

## Metrics produced

| Metric | Meaning |
|---|---|
| `ipa_healthcheck{result="SUCCESS\|WARNING\|ERROR\|CRITICAL"}` | Count of checks by severity (built-in). |
| `ipa_service_state{service="..."}` | 1 = UP, 0 = DOWN per monitored systemd unit (built-in). |
| `ipa_healthcheck_result{source="...",check="..."}` | Per-check severity 0-3 (custom). |
| `ipa_healthcheck_last_run_timestamp_seconds` | Unix time of the last export. |
| `ipa_healthcheck_duration_seconds` | How long the last healthcheck took. |
| `ipa_healthcheck_checks_total` | Total number of checks run. |
| `ipa_certificate_days_until_expiry{cert="..."}` | Days until each tracked cert expires (custom). |

## License

MIT
