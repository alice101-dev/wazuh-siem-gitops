"""Reconcile the custom detections and the dashboard of Wazuh from the content packs and dashboard.json.

The packs and the dashboard are YAML in Git; an init container converts them to JSON in CONFIG_DIR,
so this script needs nothing beyond the standard library.

Each content pack (every *.json there with an "integration" key) is a user-managed integration of
the content manager with its decoders and Sigma rules. They are written to the draft space,
promoted draft -> test -> custom, and run by a Ruleset Management detector of their own, because
the standard detectors only run standard rules. A pack may name the root decoder of the custom
space policy. Decoders and rules removed from a pack are deleted. The dashboard is written through
the Wazuh dashboard saved objects API.
"""

import base64
import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.request

INDEXER = os.environ.get("INDEXER_URL", "https://wazuh-indexer.wazuh.svc.cluster.local:9200")
DASHBOARD = os.environ.get("DASHBOARD_URL", "https://wazuh-dashboard.wazuh.svc.cluster.local")
CONFIG_DIR = os.environ.get("CONFIG_DIR", "/config")
CA_FILE = os.environ.get("CA_FILE", "/ca/ca.crt")
CREDENTIALS_FILE = os.environ.get("CREDENTIALS_FILE", "/credentials/indexer.env")
AUTHOR = "wazuh-siem-gitops"
SAVED_OBJECT_PREFIX = "gke-k8s-"
INDEX_PATTERNS = {
    "events": "wazuh-events-v5-cloud-services*",
    "findings": "wazuh-findings-v5-cloud-services*",
    "security-events": "wazuh-events-v5-security*",
    "security-findings": "wazuh-findings-v5-security*",
}


def log(message):
    print(message, flush=True)


def admin_password():
    with open(CREDENTIALS_FILE) as f:
        for line in f:
            if line.startswith("WAZUH_INDEXER_ADMIN_PASSWORD="):
                return line.split("=", 1)[1].strip()
    sys.exit("WAZUH_INDEXER_ADMIN_PASSWORD not found in " + CREDENTIALS_FILE)


def tls_context():
    return ssl.create_default_context(cafile=CA_FILE)


class Api:
    def __init__(self, base, password, extra_headers=None):
        self.base = base
        token = base64.b64encode(("admin:" + password).encode()).decode()
        self.headers = {"Authorization": "Basic " + token, "Content-Type": "application/json"}
        self.headers.update(extra_headers or {})
        self.context = tls_context()

    def call(self, method, path, body=None, ok=(200, 201)):
        data = None if body is None else json.dumps(body).encode()
        request = urllib.request.Request(self.base + path, data=data, method=method, headers=self.headers)
        try:
            with urllib.request.urlopen(request, context=self.context, timeout=60) as response:
                status, raw = response.status, response.read()
        except urllib.error.HTTPError as error:
            status, raw = error.code, error.read()
        payload = json.loads(raw) if raw else {}
        if status not in ok:
            raise RuntimeError(f"{method} {path} -> {status}: {json.dumps(payload)[:800]}")
        return status, payload


def wait_until(description, probe, attempts=60, delay=10):
    for attempt in range(1, attempts + 1):
        try:
            probe()
            return
        except Exception as error:  # the service is still starting
            log(f"{description} not ready yet ({error}); retry {attempt}/{attempts} in {delay}s")
            time.sleep(delay)
    sys.exit(f"{description} never became ready")


def search(api, index, query, size=500):
    _, result = api.call("POST", f"/{index}/_search", {"size": size, "query": query})
    return result.get("hits", {}).get("hits", [])


def space_filter(space, field, value):
    return {"bool": {"filter": [{"term": {"space.name": space}}, {"term": {field: value}}]}}


def canonical(value):
    return json.dumps(value, sort_keys=True)


# ---------------------------------------------------------------- detections


def ensure_integration(api, spec):
    title = spec["title"]
    hits = search(api, "wazuh-threatintel-integrations", space_filter("draft", "document.metadata.title", title))
    if hits:
        return hits[0]["_id"]
    _, result = api.call("POST", "/_plugins/_content_manager/integrations", {
        "resource": {
            "metadata": {"title": title, "author": AUTHOR, "description": spec["description"]},
            "category": spec["category"],
            "enabled": True,
        }
    })
    log(f"Integration {title} created ({result['message']})")
    return result["message"]


def desired_rule(rule, config):
    product = config["integration"]["title"]
    detection = {"selection": rule["selection"]}
    excluded = dict(rule.get("exclude", {}))
    if rule.get("trusted", True):
        excluded.update(config.get("trusted", {}))
    detection.update(excluded)
    condition = "selection"
    if excluded:
        condition += " and not (" + " or ".join(excluded) + ")"
    detection["condition"] = condition
    resource = {
        "metadata": {"title": rule["title"], "author": AUTHOR, "description": rule["description"]},
        "status": "experimental",
        "level": rule["level"],
        "enabled": True,
        "logsource": {"product": product, "service": "gcp.audit"},
        "detection": detection,
    }
    if "mitre" in rule:
        resource["mitre"] = {
            kind: {"id": [pair[0]], "name": [pair[1]]} for kind, pair in rule["mitre"].items()
        }
    return resource


def rule_differs(stored, resource):
    keys = ("status", "level", "enabled", "logsource", "detection", "mitre")
    for key in keys:
        if canonical(stored.get(key)) != canonical(resource.get(key)):
            return True
    meta = stored.get("metadata", {})
    return any(meta.get(k) != resource["metadata"][k] for k in ("title", "author", "description"))


def reconcile_rules(api, integration_id, config):
    product = config["integration"]["title"]
    stored = {
        hit["_source"]["document"]["metadata"]["title"]: hit
        for hit in search(api, "wazuh-threatintel-rules", space_filter("draft", "document.logsource.product", product))
    }
    wanted = set()
    for rule in config["rules"]:
        resource = desired_rule(rule, config)
        title = rule["title"]
        wanted.add(title)
        if title not in stored:
            _, result = api.call("POST", "/_plugins/_content_manager/rules", {"integration": integration_id, "resource": resource})
            log(f"Rule '{title}' created ({result['message']})")
        elif rule_differs(stored[title]["_source"]["document"], resource):
            api.call("PUT", f"/_plugins/_content_manager/rules/{stored[title]['_id']}", {"resource": resource})
            log(f"Rule '{title}' updated")
    for title, hit in stored.items():
        if title not in wanted:
            api.call("DELETE", f"/_plugins/_content_manager/rules/{hit['_id']}")
            log(f"Rule '{title}' deleted")


def desired_decoder(decoder):
    resource = {
        "name": decoder["name"],
        "enabled": True,
        "metadata": {"title": decoder["title"], "author": AUTHOR, "description": decoder["description"]},
        "normalize": decoder["normalize"],
    }
    for key in ("parents", "check"):
        if key in decoder:
            resource[key] = decoder[key]
    return resource


def decoder_differs(stored, resource):
    for key in ("enabled", "parents", "check", "normalize"):
        if canonical(stored.get(key)) != canonical(resource.get(key)):
            return True
    meta = stored.get("metadata", {})
    return any(meta.get(k) != resource["metadata"][k] for k in ("title", "author", "description"))


def reconcile_decoders(api, integration_id, pack):
    """Create, update and delete the draft decoders of the pack's integration; returns name -> id."""
    _, integration = api.call("GET", f"/wazuh-threatintel-integrations/_doc/{integration_id}")
    linked = integration.get("_source", {}).get("document", {}).get("decoders") or []
    stored = {}
    for decoder_id in linked:
        status, doc = api.call("GET", f"/wazuh-threatintel-decoders/_doc/{decoder_id}", ok=(200, 404))
        if status == 200:
            stored[doc["_source"]["document"]["name"]] = (decoder_id, doc["_source"]["document"])
    ids = {}
    for decoder in pack.get("decoders", []):  # in order: parents before children
        resource = desired_decoder(decoder)
        name = decoder["name"]
        if name not in stored:
            _, result = api.call("POST", "/_plugins/_content_manager/decoders",
                                 {"integration": integration_id, "resource": resource})
            ids[name] = result["message"]
            log(f"Decoder {name} created ({result['message']})")
            continue
        decoder_id, document = stored[name]
        ids[name] = decoder_id
        if decoder_differs(document, resource):
            api.call("PUT", f"/_plugins/_content_manager/decoders/{decoder_id}", {"resource": resource})
            log(f"Decoder {name} updated")
    wanted = {decoder["name"] for decoder in pack.get("decoders", [])}
    for name, (decoder_id, _) in reversed(list(stored.items())):  # children before parents
        if name not in wanted:
            api.call("DELETE", f"/_plugins/_content_manager/decoders/{decoder_id}")
            log(f"Decoder {name} deleted")
    return ids


def ensure_root_decoder(api, decoder_id):
    """Point the draft policy at the root decoder, keeping every other policy setting."""
    hits = search(api, "wazuh-threatintel-policies", {"term": {"space.name": "draft"}}, size=1)
    policy = hits[0]["_source"]["document"]
    if policy.get("root_decoder") == decoder_id:
        return
    meta = policy.get("metadata", {})
    api.call("PUT", "/_plugins/_content_manager/policy/draft", {"resource": {
        "metadata": {
            "title": meta.get("title") or "Custom space",
            "author": meta.get("author") or AUTHOR,
            "description": meta.get("description") or "Custom space",
            "documentation": meta.get("documentation") or "",
            "references": meta.get("references") or [],
        },
        "root_decoder": decoder_id,
        "integrations": policy.get("integrations") or [],
        "filters": policy.get("filters") or [],
        "enrichments": policy.get("enrichments") or [],
        "enabled": policy.get("enabled", True),
        "index_unclassified_events": policy.get("index_unclassified_events", False),
        "index_discarded_events": policy.get("index_discarded_events", False),
    }})
    log(f"Draft policy root decoder set to {decoder_id}")


def promote(api, space, operations=("add", "update", "remove"), rounds=3):
    """Promote the changes of a space whose operation is in operations; the policy update rides along.

    The preview lists the removal of a deleted rule only once the integration that dropped it is
    promoted, so the preview is taken again after each promotion until it is empty.
    """
    for _ in range(rounds):
        _, preview = api.call("GET", f"/_plugins/_content_manager/promote?space={space}")
        changes = {
            kind: items if kind == "policy" else [item for item in items if item["operation"] in operations]
            for kind, items in preview.get("changes", {}).items()
        }
        if not any(items for kind, items in changes.items() if kind != "policy"):
            log(f"Nothing (more) to promote from {space} ({'/'.join(operations)})")
            return
        api.call("POST", "/_plugins/_content_manager/promote", {"space": space, "changes": changes})
        summary = {kind: len(items) for kind, items in changes.items() if items and kind != "policy"}
        log(f"Promoted from {space} ({'/'.join(operations)}): {summary}")
    sys.exit(f"Promotion from {space} still has changes after {rounds} rounds")


def detector_name(hit):
    source = hit["_source"]
    return source.get("name") or source.get("detector", {}).get("name")


def reconcile_detector(api, config):
    spec = config["detector"]
    product = config["integration"]["title"]
    titles = {rule["title"] for rule in config["rules"]}
    rule_ids = sorted(
        hit["_source"]["document"]["id"]
        for hit in search(api, "wazuh-threatintel-rules", space_filter("custom", "document.logsource.product", product))
        if hit["_source"]["document"]["metadata"]["title"] in titles
    )
    body = {
        "name": spec["name"],
        "detector_type": product,
        "enabled": True,
        "schedule": {"period": {"interval": spec["interval_minutes"], "unit": "MINUTES"}},
        "inputs": [{"detector_input": {
            "description": f"Custom rules of the {product} content pack",
            "indices": spec["indices"],
            "custom_rules": [{"id": rule_id} for rule_id in rule_ids],
            "pre_packaged_rules": [],
        }}],
        "triggers": [],
        "threat_intel_enabled": False,
    }
    _, found = api.call("POST", "/_plugins/_security_analytics/detectors/_search",
                        {"size": 100, "query": {"match_all": {}}})
    existing = [hit for hit in found.get("hits", {}).get("hits", []) if detector_name(hit) == spec["name"]]
    if not rule_ids:
        log(f"No {product} rules in the custom space; detector left unchanged")
        return
    if not existing:
        _, result = api.call("POST", "/_plugins/_security_analytics/detectors", body)
        log(f"Detector {spec['name']} created ({result['_id']}) with {len(rule_ids)} rules")
        return
    detector_id = existing[0]["_id"]
    _, current = api.call("GET", f"/_plugins/_security_analytics/detectors/{detector_id}")
    detector = current["detector"]
    current_input = detector["inputs"][0]["detector_input"]
    same = (
        detector.get("enabled") is True
        and sorted(r["id"] for r in current_input.get("custom_rules", [])) == rule_ids
        and sorted(current_input.get("indices", [])) == sorted(spec["indices"])
        and detector["schedule"]["period"]["interval"] == spec["interval_minutes"]
    )
    if same:
        log(f"Detector {spec['name']} ({detector_id}) is up to date with {len(rule_ids)} rules")
        return
    api.call("PUT", f"/_plugins/_security_analytics/detectors/{detector_id}", body)
    log(f"Detector {spec['name']} ({detector_id}) updated with {len(rule_ids)} rules")


# ---------------------------------------------------------------- dashboard


def search_source(query):
    return json.dumps({
        "query": {"query": query, "language": "kuery"},
        "filter": [],
        "indexRefName": "kibanaSavedObjectMeta.searchSourceJSON.index",
    })


def terms_agg(agg_id, schema, spec):
    params = {
        "field": spec["field"], "size": spec.get("size", 10), "order": "desc", "orderBy": "1",
        "otherBucket": False, "otherBucketLabel": "Other", "missingBucket": False, "missingBucketLabel": "Missing",
    }
    if "label" in spec:
        params["customLabel"] = spec["label"]
    return {"id": agg_id, "enabled": True, "type": "terms", "schema": schema, "params": params}


COUNT = {"id": "1", "enabled": True, "type": "count", "schema": "metric", "params": {}}


def axis_params(chart_type, horizontal=False):
    category = {"id": "CategoryAxis-1", "type": "category", "position": "left" if horizontal else "bottom", "show": True,
                "style": {}, "scale": {"type": "linear"},
                "labels": {"show": True, "rotate": 0, "filter": not horizontal, "truncate": 100}, "title": {}}
    value = {"id": "ValueAxis-1", "name": "LeftAxis-1", "type": "value", "position": "bottom" if horizontal else "left",
             "show": True, "style": {}, "scale": {"type": "linear", "mode": "normal"},
             "labels": {"show": True, "rotate": 0, "filter": False, "truncate": 100}, "title": {"text": "Count"}}
    series = {"show": True, "type": "histogram" if horizontal else chart_type, "mode": "normal",
              "data": {"label": "Count", "id": "1"}, "valueAxis": "ValueAxis-1",
              "drawLinesBetweenPoints": True, "lineWidth": 2, "interpolate": "linear", "showCircles": True}
    return {"type": "histogram" if horizontal else chart_type, "grid": {"categoryLines": False},
            "categoryAxes": [category], "valueAxes": [value], "seriesParams": [series],
            "addTooltip": True, "addLegend": True, "legendPosition": "right", "times": [], "addTimeMarker": False,
            "labels": {"show": False}, "thresholdLine": {"show": False, "value": 10, "width": 1, "style": "full", "color": "#E7664C"}}


def vis_state(panel):
    kind = panel["type"]
    if kind == "metric":
        aggs = []
        for number, metric in enumerate(panel["metrics"], start=1):
            params = {"customLabel": metric["label"]}
            if "field" in metric:
                params["field"] = metric["field"]
            aggs.append({"id": str(number), "enabled": True, "type": metric["type"], "schema": "metric", "params": params})
        params = {"type": "metric", "addTooltip": True, "addLegend": False, "metric": {
            "percentageMode": False, "useRanges": False, "colorSchema": "Green to Red", "metricColorMode": "None",
            "colorsRange": [{"from": 0, "to": 10000}], "labels": {"show": True}, "invertColors": False,
            "style": {"bgFill": "#000", "bgColor": False, "labelColor": False, "subText": "", "fontSize": 36}}}
    elif kind == "pie":
        aggs = [COUNT, terms_agg("2", "segment", panel["terms"][0])]
        params = {"type": "pie", "addTooltip": True, "addLegend": True, "legendPosition": "right", "isDonut": True,
                  "labels": {"show": False, "values": True, "last_level": True, "truncate": 100}}
    elif kind == "line":
        aggs = [COUNT, {"id": "2", "enabled": True, "type": "date_histogram", "schema": "segment", "params": {
            "field": "@timestamp", "useNormalizedEsInterval": True, "scaleMetricValues": False, "interval": "auto",
            "drop_partials": False, "min_doc_count": 1, "extended_bounds": {}}}]
        if "split" in panel:
            aggs.append(terms_agg("3", "group", panel["split"]))
        params = axis_params("line")
    elif kind == "table":
        aggs = [COUNT] + [terms_agg(str(n), "bucket", t) for n, t in enumerate(panel["terms"], start=2)]
        params = {"perPage": 10, "showPartialRows": False, "showMetricsAtAllLevels": False,
                  "sort": {"columnIndex": None, "direction": None}, "showTotal": False, "totalFunc": "sum",
                  "percentageCol": "", "showToolbar": True}
    elif kind == "horizontal_bar":
        aggs = [COUNT, terms_agg("2", "segment", panel["terms"][0])]
        params = axis_params("histogram", horizontal=True)
    else:
        raise ValueError("unknown panel type " + kind)
    return json.dumps({"title": panel["title"], "type": kind, "params": params, "aggs": aggs})


def saved_objects(spec):
    objects, panels, refs = [], [], []
    x = y = row_height = 0
    for number, panel in enumerate(spec["panels"]):
        object_id = SAVED_OBJECT_PREFIX + panel["id"]
        query = spec["queries"][panel["query"]]
        if "filter" in panel:
            query = f"({query}) and ({panel['filter']})"
        reference = [{"name": "kibanaSavedObjectMeta.searchSourceJSON.index", "type": "index-pattern",
                      "id": INDEX_PATTERNS[panel["index"]]}]
        if panel["type"] == "search":
            object_type = "search"
            attributes = {"title": panel["title"], "description": "", "columns": panel["columns"],
                          "sort": [["@timestamp", "desc"]], "version": 1,
                          "kibanaSavedObjectMeta": {"searchSourceJSON": search_source(query)}}
        else:
            object_type = "visualization"
            attributes = {"title": panel["title"], "description": "", "version": 1, "uiStateJSON": "{}",
                          "visState": vis_state(panel),
                          "kibanaSavedObjectMeta": {"searchSourceJSON": search_source(query)}}
        objects.append({"type": object_type, "id": object_id, "attributes": attributes, "references": reference})
        width, height = panel["w"], panel["h"]
        if x + width > 48:
            x, y, row_height = 0, y + row_height, 0
        panels.append({"version": "3.2.0", "gridData": {"x": x, "y": y, "w": width, "h": height, "i": str(number)},
                       "panelIndex": str(number), "type": object_type, "panelRefName": f"panel_{number}",
                       "embeddableConfig": {}})
        refs.append({"name": f"panel_{number}", "type": object_type, "id": object_id})
        x += width
        row_height = max(row_height, height)
    objects.append({"type": "dashboard", "id": spec["id"], "references": refs, "attributes": {
        "title": spec["title"], "description": spec["description"], "version": 1, "timeRestore": True,
        "timeFrom": "now-24h", "timeTo": "now", "refreshInterval": {"pause": False, "value": 60000},
        "panelsJSON": json.dumps(panels), "optionsJSON": json.dumps({"useMargins": True, "hidePanelTitles": False}),
        "kibanaSavedObjectMeta": {"searchSourceJSON": json.dumps({"query": {"query": "", "language": "kuery"}, "filter": []})},
    }})
    return objects


def reconcile_dashboard(api, spec):
    objects = saved_objects(spec)
    wanted = {(o["type"], o["id"]) for o in objects}
    api.call("POST", "/api/saved_objects/_bulk_create?overwrite=true", objects)
    log(f"Dashboard '{spec['title']}' written with {len(objects) - 1} panels")
    for object_type in ("visualization", "search"):
        _, found = api.call("GET", f"/api/saved_objects/_find?type={object_type}&per_page=1000&fields=title")
        for item in found.get("saved_objects", []):
            if item["id"].startswith(SAVED_OBJECT_PREFIX) and (object_type, item["id"]) not in wanted:
                api.call("DELETE", f"/api/saved_objects/{object_type}/{item['id']}")
                log(f"Removed {object_type} {item['id']}")


def load_packs():
    packs = []
    for name in sorted(os.listdir(CONFIG_DIR)):
        if name.endswith(".json") and name != "dashboard.json":
            with open(os.path.join(CONFIG_DIR, name)) as f:
                pack = json.load(f)
            if "integration" in pack:
                packs.append(pack)
    return packs


def main():
    packs = load_packs()
    with open(os.path.join(CONFIG_DIR, "dashboard.json")) as f:
        dashboard = json.load(f)
    password = admin_password()
    indexer = Api(INDEXER, password)
    dashboards = Api(DASHBOARD, password, {"osd-xsrf": "true", "securitytenant": "global"})

    wait_until("Content manager", lambda: indexer.call("GET", "/_plugins/_content_manager/policy/resources?space=draft"))
    for pack in packs:
        integration_id = ensure_integration(indexer, pack["integration"])
        decoder_ids = reconcile_decoders(indexer, integration_id, pack)
        if "root_decoder" in pack:
            ensure_root_decoder(indexer, decoder_ids[pack["root_decoder"]])
        reconcile_rules(indexer, integration_id, pack)
    promote(indexer, "draft")
    # A removal may not leave a detector without rules: add and update first, point each
    # detector at the rules of its pack, then remove what is gone.
    promote(indexer, "test", ("add", "update"))
    for pack in packs:
        reconcile_detector(indexer, pack)
    promote(indexer, "test", ("remove",))

    wait_until("Wazuh dashboard", lambda: dashboards.call("GET", "/api/status"))
    reconcile_dashboard(dashboards, dashboard)


if __name__ == "__main__":
    main()
