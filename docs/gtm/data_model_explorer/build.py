"""Regenerates the CapHive data model explorer from the codebase.

Usage (from the repo root): python3 docs/gtm/data_model_explorer/build.py
Writes caphive_data_model.html (standalone, open in any browser) and
caphive_data_model.artifact.html (body-only, for publishing as an Artifact)
and caphive_data_dictionary.csv (one row per column, business tables only).
"""
import csv, datetime, json, os, pathlib, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
tmp1, tmp2 = HERE / ".data_raw.json", HERE / ".data.json"


def write_dictionary(raw, path):
    """One row per column, for clients who want to filter the schema in a spreadsheet."""
    doms = {d["id"]: d["name"] for d in raw["domains"]}
    with path.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["domain", "table", "table_description", "takes_custom_fields", "column", "type", "required", "default", "notes"])
        for name, t in sorted(raw["tables"].items(), key=lambda kv: (kv[1]["tier"] == "internal", kv[1]["domain"], kv[0])):
            if t["tier"] == "internal":
                continue
            money = {m + "_cents" for m in t["money"]}
            fks = {(a.get("fk") or a["name"] + "_id"): a for a in t.get("assocs", []) if a["macro"] == "belongs_to"}
            for c in t["columns"]:
                notes = []
                if c["name"] in money:
                    notes.append(f"money in cents; API field {c['name'][:-6]}")
                a = fks.get(c["name"])
                if a and a.get("poly"):
                    notes.append("references any record (polymorphic)")
                elif a and a.get("table"):
                    notes.append(f"references {a['table']}")
                if c["name"] == "json_fields":
                    notes.append("custom field values")
                notes += [x for x in (c.get("desc"), c.get("comment")) if x]
                ty = c["type"] + (f"({c['limit']})" if c.get("limit") else "") + (f"({c['precision']})" if c.get("precision") else "")
                w.writerow([doms[t["domain"]], name, t.get("blurb") or t.get("description") or "", "yes" if t.get("custom_fields") else "",
                            c["name"], ty, "yes" if c.get("null") is False else "", c.get("default", ""), "; ".join(notes)])
# Runtime reflection needs Rails to boot; without it the static parse of the model files is used.
# Override the command with RAILS_CMD, e.g. RAILS_CMD="rvm 3.4.1 do bin/rails".
reflect = HERE / ".models.json"
rails = os.environ.get("RAILS_CMD", "bin/rails").split()
r = subprocess.run(rails + ["runner", str(HERE / "reflect_models.rb"), str(reflect)], cwd=ROOT, capture_output=True, text=True)
if r.returncode != 0:
    print("rails runner failed; falling back to the static model parse:", r.stderr.strip().splitlines()[:1])
subprocess.run([sys.executable, "-I", str(HERE / "extract.py"), str(ROOT), str(tmp1), str(reflect)], check=True)
reflect.unlink(missing_ok=True)
subprocess.run([sys.executable, "-I", str(HERE / "domains.py"), str(tmp1), str(tmp2)], check=True)
raw = json.loads(tmp2.read_text())
data = json.dumps(raw, separators=(",", ":")).replace("</", "<\\/")
write_dictionary(raw, HERE / "caphive_data_dictionary.csv")
tmp1.unlink(); tmp2.unlink()
today = datetime.date.today().strftime("%b %d, %Y")
body = (HERE / "template.html").read_text().replace("__GENERATED__", today).replace("__DATA__", data)
(HERE / "caphive_data_model.artifact.html").write_text(body)
standalone = ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
              '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
              '<style>[hidden]{display:none!important}body{margin:0}</style>\n</head>\n<body>\n' + body + "\n</body>\n</html>\n")
(HERE / "caphive_data_model.html").write_text(standalone)
print("wrote", HERE / "caphive_data_model.html", f"{len(standalone)//1024} KB")
