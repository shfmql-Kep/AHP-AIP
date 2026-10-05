import requests, time, json, sys, urllib.parse
OUT = sys.argv[1]
BASE = "https://api.openalex.org/works"
FIELDS = "id,doi,title,publication_year,publication_date,type,cited_by_count,primary_location,abstract_inverted_index,authorships,language,open_access,keywords,topics"

Q = {
 "AM_replace_opt": '("asset replacement" OR "replacement planning" OR "renewal planning" OR "asset renewal" OR "replacement strategy") AND (distribution OR transformer OR cable OR substation OR "power system" OR "electricity network") AND (optimization OR optimisation OR planning OR prioritization OR prioritisation)',
 "AM_risk_based": '("risk-based" OR "risk based" OR "risk-informed") AND ("asset management" OR maintenance) AND (power OR electrical OR grid OR utility)',
 "AM_AIP_portfolio": '("asset investment planning" OR "capital investment" OR "investment portfolio" OR "investment prioritization") AND (utility OR "power system" OR electrical OR grid OR "electricity network")',
 "OPT_sensitivity_unc": '("global sensitivity" OR "Sobol" OR "uncertainty propagation" OR "parameter uncertainty" OR "value of information") AND ("asset management" OR "maintenance" OR "replacement") AND (power OR electrical OR transformer OR cable)',
 "AM_transformer_fleet": '("transformer fleet" OR "power transformer" OR "distribution transformer") AND (replacement OR "end of life" OR "remaining life" OR "life cycle cost") AND (optimization OR planning OR decision)',
 "PS_cable_aging": '("underground cable" OR "XLPE cable" OR "distribution cable") AND (aging OR failure OR replacement OR "asset management")',
 "PS_switchgear": '("switchgear" OR "recloser" OR "sectionalizer" OR "ring main unit") AND (reliability OR "asset management" OR replacement OR "condition monitoring")',
}

def inv2text(inv):
    if not inv: return ""
    pos = {}
    for w, ps in inv.items():
        for p in ps: pos[p] = w
    return " ".join(pos[k] for k in sorted(pos))

def fetch(q, sort, frm, n):
    out, cursor = [], "*"
    filt = f'title_and_abstract.search:{q},from_publication_date:{frm},type:article|preprint'
    while len(out) < n and cursor:
        params = {"filter": filt, "sort": sort, "per-page": 100, "cursor": cursor, "select": FIELDS}
        for attempt in range(4):
            try:
                r = requests.get(BASE, params=params, timeout=40)
                if r.status_code == 200: break
                time.sleep(2 + attempt * 3)
            except Exception as e:
                time.sleep(3)
        else:
            print("  FAIL", q[:40]); break
        j = r.json()
        res = j.get("results", [])
        if not res: break
        out.extend(res); cursor = j["meta"].get("next_cursor")
        time.sleep(0.15)
    return out[:n], (j["meta"].get("count") if 'j' in locals() else None)

seen = {}
with open(OUT, "w", encoding="utf8") as f:
    for tag, q in Q.items():
        tot = None
        for sort, frm, n in [("cited_by_count:desc", "2014-01-01", 250), ("publication_date:desc", "2024-06-01", 120)]:
            res, cnt = fetch(q, sort, frm, n)
            tot = cnt if tot is None else tot
            new = 0
            for w in res:
                wid = w["id"]
                if wid in seen:
                    seen[wid]["tags"].add(tag); continue
                loc = (w.get("primary_location") or {}).get("source") or {}
                rec = {"id": wid, "doi": w.get("doi"), "title": w.get("title"), "year": w.get("publication_year"),
                       "date": w.get("publication_date"), "type": w.get("type"), "cites": w.get("cited_by_count"),
                       "venue": loc.get("display_name"), "lang": w.get("language"),
                       "abstract": inv2text(w.get("abstract_inverted_index")),
                       "authors": "; ".join((a.get("author") or {}).get("display_name", "") for a in (w.get("authorships") or [])[:4]),
                       "topics": "; ".join(t.get("display_name", "") for t in (w.get("topics") or [])[:3]),
                       "oa": ((w.get("open_access") or {}).get("oa_url")), "tags": {tag}}
                seen[wid] = rec; new += 1
            print(f"{tag:26s} sort={sort[:8]} got={len(res)} new={new} total_matches~{cnt}", flush=True)
    for rec in seen.values():
        rec["tags"] = sorted(rec["tags"])
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")
print("TOTAL", len(seen))
