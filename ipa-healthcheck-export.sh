#!/usr/bin/env bash
# Export ipa-healthcheck results as a Prometheus textfile.
#
# Runs ipa-healthcheck twice (built-in prometheus output + JSON), expands the
# JSON into per-check metrics with a small Python parser, then writes the
# combined file atomically with mv so node_exporter never reads a partial scrape.
#
# Install to /usr/local/bin/ipa-healthcheck-export.sh and drive it from the
# systemd timer (see systemd/). Companion to:
# https://computingforgeeks.com/freeipa-healthcheck-prometheus-grafana/

OUT="/var/lib/node_exporter/textfile_collector/ipa_healthcheck.prom"
TMP=$(mktemp)
JSON=$(mktemp)

START=$(date +%s)
ipa-healthcheck --output-type json > "$JSON" 2>/dev/null || true
END=$(date +%s)

# Built-in aggregates: ipa_healthcheck{result=...} and ipa_service_state{service=...}
ipa-healthcheck --output-type prometheus >> "$TMP" 2>/dev/null || true

# Custom per-check expansion + cert expiry
python3 - "$JSON" "$START" "$END" <<'PY' >> "$TMP"
import json, sys, re
path, start, end = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
levels = {"SUCCESS": 0, "WARNING": 1, "ERROR": 2, "CRITICAL": 3}
data = json.load(open(path))

print(f"ipa_healthcheck_last_run_timestamp_seconds {end}")
print(f"ipa_healthcheck_duration_seconds {end-start}")
print(f"ipa_healthcheck_checks_total {len(data)}")

seen = {}
for c in data:
    key = (c["source"], c["check"])
    res = levels.get(c.get("result","SUCCESS"), -1)
    if key not in seen or seen[key] < res:
        seen[key] = res
for (src, chk), res in seen.items():
    print(f'ipa_healthcheck_result{{source="{src}",check="{chk}"}} {res}')

for c in data:
    if "expir" in c.get("check","").lower():
        days = c.get("kw",{}).get("days")
        if isinstance(days, int):
            key = c["kw"].get("key","unknown")
            print(f'ipa_certificate_days_until_expiry{{cert="{key}"}} {days}')
PY

mv "$TMP" "$OUT"
chmod 0644 "$OUT"
