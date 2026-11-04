"""Builds data.json for the schema explorer from schema.rb, model files, MCP ontology and swagger."""
import json, re, sys, pathlib, yaml

ROOT = pathlib.Path(sys.argv[1])
OUT = pathlib.Path(sys.argv[2])

# ---------- schema.rb ----------
tables = {}
cur = None
for line in (ROOT / "db/schema.rb").read_text().splitlines():
    m = re.match(r'\s*create_table "(\w+)"(.*) do \|t\|', line)
    if m:
        opts = m.group(2)
        pk = re.search(r'primary_key: (\[[^\]]+\]|"\w+")', opts)
        cur = {"name": m.group(1), "columns": [{"name": "id", "type": "bigint", "null": False, "pk": True}],
               "indexes": [], "pk": pk.group(1).replace('"', "") if pk else "id"}
        if "id: false" in opts:
            cur["columns"] = []
        tc = re.search(r'comment: "([^"]*)"', opts)
        if tc:
            cur["comment"] = tc.group(1)
        tables[cur["name"]] = cur
        continue
    if cur is None:
        continue
    if re.match(r"\s*end\s*$", line):
        cur = None
        continue
    m = re.match(r'\s*t\.(\w+) "(\w+)"(.*)$', line)
    if m:
        typ, name, rest = m.groups()
        col = {"name": name, "type": typ}
        if "null: false" in rest:
            col["null"] = False
        d = re.search(r'default: ("[^"]*"|[^,]+)', rest)
        if d:
            col["default"] = d.group(1).strip().strip('"')
        lim = re.search(r"limit: (\d+)", rest)
        if lim:
            col["limit"] = int(lim.group(1))
        pr = re.search(r"precision: (\d+), scale: (\d+)", rest)
        if pr:
            col["precision"] = f"{pr.group(1)},{pr.group(2)}"
        c = re.search(r'comment: "([^"]*)"', rest)
        if c:
            col["comment"] = c.group(1)
        if cur["name"] == "account_entries" and name == "id":
            continue
        cur["columns"].append(col)
        continue
    m = re.match(r'\s*t\.index \[([^\]]+)\](.*)$', line)
    if m:
        cols = [c.strip().strip('"') for c in m.group(1).split(",")]
        cur["indexes"].append({"columns": cols, "unique": "unique: true" in m.group(2)})

# ---------- models ----------
ASSOC = re.compile(r"^\s*(belongs_to|has_many|has_one|has_and_belongs_to_many)\s+:(\w+)(.*)$")
models = {}
for f in ROOT.glob("app/**/models/**/*.rb"):
    src = f.read_text(errors="ignore")
    m = re.search(r"^class (\w+) < (\w+)", src, re.M)
    if not m:
        continue
    klass, parent = m.groups()
    if klass.endswith("Sqlite") or parent in ("ApplicationRecordSqlite",):
        continue
    pack = re.search(r"app/packs/([^/]+/[^/]+)/", str(f))
    tn = re.search(r'self\.table_name\s*=\s*"(\w+)"', src)
    info = {"model": klass, "parent": parent, "pack": pack.group(1) if pack else None,
            "table_name": tn.group(1) if tn else None,
            "custom_fields": bool(re.search(r"include WithCustomField", src)),
            "money": [], "assocs": [], "file": str(f.relative_to(ROOT))}
    for mm in re.finditer(r"^\s*monetize\s+((?::\w+,?\s*)+)", src, re.M):
        info["money"] += [x.removesuffix("_cents") for x in re.findall(r":(\w+)", mm.group(1))]
    for line in src.splitlines():
        a = ASSOC.match(line)
        if not a:
            continue
        macro, name, rest = a.groups()
        h = {"macro": macro, "name": name}
        cn = re.search(r'class_name:\s*"(\w+(?:::\w+)*)"', rest)
        if cn:
            h["class"] = cn.group(1)
        if "polymorphic: true" in rest:
            h["poly"] = True
        th = re.search(r"through:\s*:(\w+)", rest)
        if th:
            h["through"] = th.group(1)
        asn = re.search(r"as:\s*:(\w+)", rest)
        if asn:
            h["as"] = asn.group(1)
        fk = re.search(r'foreign_key:\s*:?"?(\w+)', rest)
        if fk:
            h["fk"] = fk.group(1)
        if not any(x["name"] == name and x["macro"] == macro for x in info["assocs"]):
            info["assocs"].append(h)
    models[klass] = info

def tableize(k):
    s = re.sub(r"(?<!^)(?=[A-Z])", "_", k).lower()
    if s.endswith("y") and not s.endswith(("ay", "ey", "oy", "uy")):
        return s[:-1] + "ies"
    if s.endswith(("s", "x", "ch", "sh")):
        return s + "es"
    return s + "s"

IRREG = {"KycData": "kyc_data"}
def table_for(klass):
    info = models.get(klass)
    if not info:
        return None
    if info["table_name"]:
        return info["table_name"]
    if info["parent"] not in ("ApplicationRecord", "ActiveRecord::Base") and info["parent"] in models:
        return table_for(info["parent"])
    return IRREG.get(klass) or tableize(klass)

for k, info in models.items():
    t = table_for(k)
    if t in tables:
        tbl = tables[t]
        base = info["parent"] in ("ApplicationRecord", "ActiveRecord::Base") or info["parent"] not in models
        if base:
            tbl["model"] = k
            tbl["pack"] = info["pack"]
            tbl["file"] = info["file"]
            tbl["custom_fields"] = tbl.get("custom_fields", False) or info["custom_fields"]
            tbl["money"] = sorted(set(tbl.get("money", []) + info["money"]))
            tbl["assocs"] = info["assocs"]
        else:
            tbl.setdefault("subclasses", []).append(k)
            tbl["custom_fields"] = tbl.get("custom_fields", False) or info["custom_fields"]

model_table = {k: table_for(k) for k in models}

# resolve association targets to tables
for t in tables.values():
    for a in t.get("assocs", []):
        if a.get("poly"):
            continue
        if a.get("through"):
            continue
        cls = a.get("class")
        if not cls:
            n = a["name"]
            if a["macro"] in ("has_many", "has_and_belongs_to_many"):
                # singularize naive
                if n.endswith("ies"):
                    n = n[:-3] + "y"
                elif n.endswith("ses") or n.endswith("xes"):
                    n = n[:-2]
                elif n.endswith("s"):
                    n = n[:-1]
            cls = "".join(p.capitalize() for p in n.split("_"))
        tt = model_table.get(cls)
        if tt in tables:
            a["table"] = tt

# money columns: any *_cents column is a money column
for t in tables.values():
    cents = [c["name"].removesuffix("_cents") for c in t["columns"] if c["name"].endswith("_cents")]
    t["money"] = sorted(set(t.get("money", []) + cents))
    t["json_cols"] = [c["name"] for c in t["columns"] if c["type"] == "json" or c["name"] in ("json_fields", "properties", "meta_data")]
    t["has_json_fields"] = any(c["name"] == "json_fields" for c in t["columns"])

# ---------- runtime reflection (optional, more complete than the static parse) ----------
REFLECT = pathlib.Path(sys.argv[3]) if len(sys.argv) > 3 else None
if REFLECT and REFLECT.exists():
    refl = json.loads(REFLECT.read_text())
    klass_table = {m["model"]: tn for tn, ms in refl.items() for m in ms}
    for tn, ms in refl.items():
        if tn not in tables:
            continue  # model whose table is no longer in schema.rb
        base = next((m for m in ms if not m.get("sti")), ms[0])
        t = tables[tn]
        t["model"] = base["sti"] or base["model"]
        t["custom_fields"] = any(m["custom_fields"] for m in ms)
        t["money"] = sorted({x.removesuffix("_cents") for x in base["money"]} | set(t.get("money", [])))
        subs = sorted(m["model"] for m in ms if m.get("sti"))
        if subs:
            t["subclasses"] = subs
        assocs = []
        for a in base["assocs"]:
            h = {"macro": a["macro"], "name": a["name"]}
            for k in ("poly", "through", "as", "fk"):
                if a.get(k):
                    h[k] = a[k]
            if a.get("klass") and not a.get("through"):
                tt = klass_table.get(a["klass"])
                if tt in tables:
                    h["table"] = tt
            assocs.append(h)
        t["assocs"] = assocs
    print("merged runtime reflection for", sum(1 for tn in refl if tn in tables), "tables")

# ---------- ontology ----------
onto = {}
for f in (ROOT / "app/packs/ai/mcp_server/ontology").glob("*.yml"):
    y = yaml.safe_load(f.read_text())
    m = y.get("model")
    tt = model_table.get(m)
    if y["entity"] == "portfolio_company":
        continue
    if tt in tables:
        tables[tt]["description"] = " ".join(y.get("description", "").split())
        tables[tt]["label"] = y.get("label")
        for fname, fd in (y.get("fields") or {}).items():
            target = fd.get("stored_as", fname)
            for c in tables[tt]["columns"]:
                if c["name"] == target and fd.get("description"):
                    c["desc"] = " ".join(fd["description"].split())

# ---------- swagger ----------
sw = yaml.safe_load((ROOT / "swagger/v1/swagger.yaml").read_text())
api = {"schemas": {}, "resources": {}}
for name, s in sw["components"]["schemas"].items():
    api["schemas"][name] = {k: {kk: vv for kk, vv in v.items() if kk in ("type", "format", "nullable", "example", "description")}
                            for k, v in (s.get("properties") or {}).items()}
for path, ops in sw["paths"].items():
    res = path.strip("/").split("/")[0].replace(".json", "")
    for verb, op in ops.items():
        if verb not in ("get", "post", "put", "patch", "delete"):
            continue
        ref = None
        try:
            sch = op["responses"]["200"]["content"]["application/json"]["schema"]
            ref = (sch.get("$ref") or sch.get("items", {}).get("$ref", "")).split("/")[-1] or None
        except (KeyError, TypeError, AttributeError):
            pass
        params = [p.get("name") for p in op.get("parameters", []) if isinstance(p, dict)]
        api["resources"].setdefault(res, []).append({"verb": verb.upper(), "path": path, "summary": op.get("summary", ""),
                                                      "schema": ref, "params": params})

data = {"tables": tables, "api": api}
OUT.write_text(json.dumps(data, separators=(",", ":")))
print(len(tables), "tables;", sum(1 for t in tables.values() if t.get("model")), "with models;",
      sum(1 for t in tables.values() if t.get("custom_fields")), "custom-field tables;",
      sum(len(v) for v in api["resources"].values()), "operations")
print("no model:", [t for t, v in tables.items() if not v.get("model")])
