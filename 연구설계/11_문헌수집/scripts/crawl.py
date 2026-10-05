import requests, time, json, sys, urllib.parse
OUT = sys.argv[1]
BASE = "https://api.openalex.org/works"
FIELDS = "id,doi,title,publication_year,publication_date,type,cited_by_count,primary_location,abstract_inverted_index,authorships,language,open_access,keywords,topics"

Q = {
 "AM_replace_opt": '("asset replacement" OR "replacement planning" OR "renewal planning" OR "asset renewal") AND (distribution OR transformer OR cable OR substation OR "power system" OR "electricity network") AND (optimization OR optimisation OR planning OR prioriti*)',
 "AM_risk_based": '("risk-based" OR "risk based" OR "risk-informed") AND ("asset management" OR maintenance) AND (power OR electric* OR grid OR utility)',
 "AM_AIP_portfolio": '("asset investment planning" OR "capital investment" OR "investment portfolio" OR "investment prioriti*") AND (utility OR "power system" OR "electric*" OR grid OR network)',
 "AM_health_index": '("health index" OR "condition assessment" OR "condition-based risk") AND (transformer OR cable OR switchgear OR "overhead line" OR "power equipment")',
 "AM_CNAIM": '("CNAIM" OR "Common Network Asset Indices" OR "network asset risk metric" OR "NARM" OR "monetised risk" OR "monetized risk")',
 "AM_failure_model": '("failure rate" OR "probability of failure" OR "survival analysis" OR "Weibull") AND (transformer OR cable OR "distribution network" OR "power grid") AND (data OR Bayesian OR "machine learning")',
 "AM_sparse_data": '(Bayesian OR "transfer learning" OR hierarchical OR "limited data" OR "data scarcity" OR "sparse data") AND ("failure" OR "asset management" OR "remaining life") AND (power OR grid OR transformer OR cable)',
 "AM_maintenance_opt": '(maintenance OR "preventive maintenance") AND (optimization OR scheduling) AND ("power distribution" OR "distribution network" OR "distribution system" OR substation)',
 "AM_MCDM": '("AHP" OR "analytic hierarchy" OR "fuzzy AHP" OR "best-worst" OR "multi-criteria") AND (transformer OR "asset management" OR "power distribution" OR "replacement priority")',
 "AM_dfl_pdm": '("decision-focused" OR "predict-then-optimize" OR "estimate-then-optimize" OR "integrated estimate and optimize") AND (maintenance OR replacement OR "power")',
 "AM_digital_twin": '("digital twin" OR "large language model" OR LLM) AND ("asset management" OR "predictive maintenance") AND (power OR grid OR utility OR transformer)',
 "PS_reliability_topology": '("reliability evaluation" OR "reliability assessment" OR "reliability analysis") AND ("distribution system" OR "distribution network") AND (SAIDI OR SAIFI OR topology OR sectionalizing OR "load transfer" OR restoration)',
 "PS_reliability_investment": '("reliability" AND (investment OR planning OR "cost-benefit")) AND ("distribution network" OR "distribution system") AND (aging OR replacement OR "equipment")',
 "PS_importance": '("importance measure" OR "Birnbaum" OR "Fussell-Vesely" OR "component criticality" OR "critical component" OR "minimal cut set" OR "fault tree") AND ("power system" OR substation OR "distribution" OR grid)',
 "PS_substation_PRA": '(substation) AND (("probabilistic risk" OR "risk assessment" OR reliability OR "fault tree" OR "Monte Carlo") AND (maintenance OR replacement OR investment OR "single point"))',
 "PS_resilience": '(resilience OR hardening OR undergrounding) AND ("distribution" OR "power grid") AND (investment OR planning OR optimization) AND (typhoon OR wildfire OR "extreme weather" OR hurricane OR flood)',
 "PS_load_growth_xfmr": '("transformer" AND (overload OR "thermal aging" OR "hot-spot" OR "loss of life")) AND ("electric vehicle" OR "heat pump" OR "photovoltaic" OR "load growth" OR electrification)',
 "PS_reconfig_reliability": '("network reconfiguration" OR "feeder reconfiguration" OR "tie switch" OR "sectionalizing switch") AND (reliability OR SAIDI OR "energy not supplied" OR "switch placement")',
 "PS_planning_aging": '("distribution planning" OR "grid planning" OR "network planning") AND (aging OR "asset condition" OR "asset health" OR replacement) AND (uncertainty OR stochastic OR robust)',
 "PS_regulation_kpi": '(SAIDI OR "customer minutes lost" OR "interruption incentive" OR "quality of supply regulation") AND (investment OR expenditure OR "asset management" OR regulation) AND (distribution OR DNO OR DSO)',
 "OPT_robust_portfolio": '("distributionally robust" OR "robust optimization" OR "chance-constrained" OR "stochastic programming" OR "regret") AND (replacement OR "asset management" OR "capital planning" OR "maintenance") AND (power OR infrastructure OR utility)',
 "OPT_sensitivity_unc": '("global sensitivity" OR "Sobol" OR "uncertainty propagation" OR "parameter uncertainty" OR "value of information") AND ("asset management" OR "maintenance" OR "replacement") AND (power OR electric* OR infrastructure)',
 "KR_distribution": '(Korea OR KEPCO OR Korean) AND ("asset management" OR "distribution system" OR "distribution network" OR "power equipment" OR transformer) AND (reliability OR replacement OR investment OR maintenance)',
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
