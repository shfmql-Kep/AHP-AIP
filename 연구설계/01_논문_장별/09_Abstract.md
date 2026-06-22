# Abstract

## A Priority-Number-Based Five-Year Portfolio Optimization Model for Distribution Asset Investment Planning

[Name]

Department of Electrical Engineering, Graduate School, Mokpo National University  
(Supervised by Professor [Supervisor Name])

This study addresses a portfolio decision problem in distribution asset investment planning (AIP). Conventional risk-based rankings are useful for identifying high-risk assets, but they do not directly solve the multi-year investment problem of determining which distribution assets should be replaced in which year under annual budget and replacement-capacity constraints.

The proposed framework combines CNAIM-based probability of failure (PoF), outage duration, connected customers, replacement cost, and risk reduction effects for a five-year planning horizon from 2026 to 2030. The pilot dataset consists of synthetic distribution assets across six major asset types: pole transformers, ground transformers, overhead switches, underground switches, overhead distribution lines, and underground cables. Each asset can be replaced at most once during the planning period, and annual budget and annual quantity constraints are explicitly imposed.

Risk reduction is defined as the difference between the cumulative risk of the existing asset over its design life from the replacement year and the cumulative risk of a new asset over the same design-life horizon. Investment value is defined as risk reduction minus replacement cost, and investment efficiency is defined as risk reduction divided by replacement cost. This distinction separates the current risk level from the long-term investment effect of replacement.

The simulation is organized into three stages. First, single-metric optimization is performed by asset type using risk greedy selection, investment-value greedy selection, investment-value ILP, and investment-value GA. Second, Priority Number (PI) is calculated by combining economic, reliability, safety, and environmental criteria, and PI-based greedy, ILP, and GA results are compared with investment-value-based results. Third, integrated asset optimization is examined by comparing a post-weighting approach using asset-type weights and a pre-calculated integrated PI approach applied to the entire asset set.

The contribution of this study is not to claim the universal superiority of a particular algorithm. Rather, it proposes a structured AIP workflow that distinguishes current risk, risk reduction, investment value, investment efficiency, SAIDI, and PI, and connects these metrics to a multi-year portfolio decision model. AHP is used as the primary method for reflecting expert judgments, while fuzzy adjustment is used as a supplementary procedure for examining the robustness of weights under qualitative uncertainty.

**Keywords**: Asset Investment Planning, AIP, CNAIM, Risk Reduction, Investment Value, Investment Efficiency, SAIDI, Priority Number, AHP, Fuzzy Adjustment, Integer Linear Programming, Genetic Algorithm, Distribution Assets, Portfolio Optimization

---

