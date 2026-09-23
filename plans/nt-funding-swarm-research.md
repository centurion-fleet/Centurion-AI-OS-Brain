# NT Funding for Swarm — Research (verified)

Prepared: 17 Aug 2026 · Titus (Centurion #3, Fleet Overseer) · Kanban swarm "NT funding for Swarm"

Scope: Northern Territory (Australia) government and federal-north funding programs that could fund the Centurion **Swarm** product — sovereign distributed AI-compute hardware (Swarm node = MSI workstation, 4× RTX 4090; + up to 5× Jetson Orin NX 16GB edge agents) targeting Australian government. Source memo: `plans/swarm-node-investment-memorandum.md` (equity seed-raise doc, $8–10M seed at $25–30M pre; 500-node fleet = $8.1M CAPEX; NSW beachhead; IRAP certification required).

---

## 0. Verification method (honest read)

This run verified against **primary pages fetched directly** (curl, 200 responses). Two constraints shaped what could and could not be confirmed:

- **All NT Government domains are Cloudflare-walled to bots** — `nt.gov.au`, `business.nt.gov.au`, `industry.nt.gov.au`, `dtc.nt.gov.au`, `invest.nt.gov.au`, `investmentterritory.nt.gov.au` all returned 403 / "Just a moment…" to both curl and the headless browser. Live NT grant listings, amounts, and deadlines **cannot be verified programmatically** and must be checked on the portal by a human.
- **All search engines were bot-blocked or degraded** this session (DuckDuckGo CAPTCHA, Google redirect, Bing serving irrelevant UK results on Australia-specific queries). So "prove a negative" searches (e.g. confirming an NT grant does NOT exist) are weak evidence, not proof.

What IS solid: the primary-source facts in §1–§3 below were read directly from each program's own non-walled website.

---

## 1. NAIF — Northern Australia Infrastructure Facility (PRIMARY, large-scale)

**Status: VERIFIED (naif.gov.au, fetched this session).**

- **What:** "NAIF is a Commonwealth Government financier, providing **concessional loans** for the development of infrastructure projects in **northern Australia and the Australian Indian Ocean Territories**." (verbatim, naif.gov.au)
- **Facility size: $7 billion.** Verbatim from the 01 Jul 2026 ministerial release: "The Albanese Government has secured the long-term future of the **$7 billion** Northern Australia Infrastructure Facility (NAIF), ensuring it will continue to invest in jobs and opportunities across the north **for a further decade**." → renewed/continued, not sunsetting.
- **Sectors supported** (verbatim): Agriculture and Water, **Energy**, **Financing Partnerships**, Resources, **Social Infrastructure**, Transport and Logistics.
- **Current performance** (30 June 2026): 35 projects, **$4.5B** value of investment decisions, $33.4B public-benefit forecast, 18,700+ forecast jobs. Separately "NAIF hits **$3 billion** milestone" (22 May 2026 ministerial release).
- **Active NT precedent:** "Campus Living Villages (CLV) Student Accommodation Project in **Darwin, Northern Territory**" — investment decision February 2026, Social Infrastructure. NAIF is currently deploying into the NT, not just eligible on paper.
- **Fit for Swarm:** this is the only realistic *large* funding instrument for the 500-node fleet (~$8.1M CAPEX). It is **concessional project debt, not a grant**, and requires a bankable project + public-benefit case (jobs, regional income, local suppliers, Indigenous outcomes — all of which NAIF screens for explicitly). The Swarm "sovereign compute + local jobs + regional public benefit" narrative maps onto NAIF's mandate. Frame as **Energy + Financing Partnerships + Social Infrastructure**, not as a small-business grant.

## 2. AMEF — Advanced Manufacturing Ecosystem Fund

**Status: VERIFIED (amgc.org.au/amef/) — CLOSED.**

- "The Advanced Manufacturing Ecosystem (AME) Fund of **$7.5 million** aims to develop the manufacturing ecosystem in the **Northern Territory**."
- "In **May 2025**, the Advanced Manufacturing Ecosystem Fund was **fully committed**. Therefore, we are **no longer accepting new applications** or progressing incomplete submissions." (verbatim)
- **Why it still matters:** confirms the NT + Commonwealth **co-investment model** exists and that AMGC (Advanced Manufacturing Growth Centre) is the delivery partner. Cite as *precedent*, never as an *open opportunity*.

## 3. CRCNA — Cooperative Research Centre for Developing Northern Australia

**Status: VERIFIED (crcna.com.au).**

- "The CRCNA works across **northern Australia which includes all of the Northern Territory** and those parts of Queensland and Western Australia that intersect with or are above the Tropic of Capricorn."
- Runs periodic **EOI funding calls** (nav includes "EOI Funding Call Guidelines"); funded as part of the Australian Government's CRC Program, supported by northern jurisdictional governments.
- **Fit:** grant-based (non-dilutive) co-funding for R&D/commercialisation of the Swarm orchestration layer, edge-agent software, and the feed-in-tariff marketplace. Smaller than NAIF; complementary.

---

## 4. The "Ignite Program Stream B" claim — DEBUNKED / UNVERIFIABLE

The prior Draft worker's primary target was **"Ignite Program Stream B — $15K, deadline 07 Sep 2026"** and a secondary **"Territory Growth Initiative"**. This research could find **no such NT program**:

- Bing search for "Ignite" + "Northern Territory" + grant returned only UK "Ignite" programs (L&G Mortgage Club, Microsoft Ignite, UK social-enterprise competitions) — **zero NT Government results**.
- The names do not appear in the source memo (348 lines, zero mention of "Ignite", "Stream B", or "Territory Growth Initiative").
- The names do not match the standard NT program set (§5).

**Conclusion:** "Ignite Program Stream B ($15K)" and "Territory Growth Initiative" are **not verifiable against any primary or reliable secondary source**, and are almost certainly fabricated by the prior Draft run. **They must not be cited in any application.** A human must confirm the *actual* current NT grant names on the portal (§5).

## 5. NT Government grant programs — NAMED but UNVERIFIED (Cloudflare wall)

These are the standard NT business/innovation programs a Swarm application would target. **Names are from domain knowledge and the prior research, NOT verified this session** — `business.nt.gov.au` (the authoritative "Grants & funding" page) is Cloudflare-walled to bots. Do not quote amounts/deadlines without a human portal check.

- **Business Growth Program (BGP)** — NT Government matched funding for business capability/projects; the most-cited general NT SME grant.
- **Local Jobs Fund** — NT co-investment / concessional finance for projects creating local jobs (fits "nodes deployed = local technician jobs").
- **Business Innovation / Innovation grant** — smaller innovation/commercialisation grant.
- **Territory Innovation Challenge** — annual innovation prize (brand/visibility value, low dollar).
- **Paspalis Innovation Investment Fund (PIIF)** — Darwin-based VC/co-investment, historically NT-Government co-funded.
- **Investment Territory** — NT's investment-attraction agency; entry point for tailored facilitation of a sovereign-compute project.
- **Defence & Aerospace NT / DefenceNT** — NT defence-industry arm; route into Pine Gap / base-adjacent sovereign-compute procurement.

**Verification path (for the Draft / a human):** `business.nt.gov.au` → "Grants & funding" (also the NT SmartyGrants portal), plus Investment Territory directly. A real browser is required.

## 6. NT entity eligibility — HARD GATE, principal decision required

Every NT grant/co-investment program requires an **NT-based entity or NT-operating presence** to be eligible. Current Centurion corporate structure (from Brain memory) is **Centurion Licensing DMCC (Dubai)** holding IP, UK wound down — **no NT entity**. This is a **blocking eligibility question for the principal (Adrian / Steve White)** before any NT grant application can proceed:

- Establish an NT entity / NT operating presence, OR
- Route through a federal instrument (NAIF, R&D Tax Incentive, NRF — none require NT incorporation, only NT *project location*), OR
- Pursue the federal/defence procurement lane instead of NT grants.

## 7. Federal programs that stack with an NT play (not jurisdiction-gated)

- **R&D Tax Incentive** — refundable offset (43.5% for small entities) on eligible R&D; Swarm orchestration + edge-agent stack is clearly eligible.
- **National Reconstruction Fund (NRF)** — $15B, incl. "enabling capabilities"; possible co-investment.
- **Industry Growth Program (IGP)** — federal grants (up to ~$5M) for SMEs commercialising advanced tech.
- **Defence — Sovereign Industrial Capability / Defence innovation** — highest-value procurement lane (Pine Gap adjacency, MRF-D, RAAF Darwin).
- **IRAP** — not funding, but the certification gate the memo already flags (Series A trigger #2).

---

## 8. Bottom line for the swarm

1. **Lead with NAIF ($7B concessional, NT-eligible, renewed 1 Jul 2026 for a further decade, active Darwin investment in Feb 2026)** as the primary large-scale instrument for the 500-node fleet — framed as Energy + Social Infrastructure + public-benefit sovereign compute. This is the *only* instrument that reaches $8.1M CAPEX scale.
2. **NT small grants (BGP, Local Jobs Fund) are seed/pilot credibility only** — they are small, get fully committed fast (AMEF precedent), and are **Cloudflare-walled so their current amounts/deadlines are unverified**. Do not build the raise thesis on them.
3. **AMEF is CLOSED (May 2025)** — cite as precedent, never as open.
4. **"Ignite Program Stream B ($15K)" and "Territory Growth Initiative" are unverifiable / likely fabricated — drop them.**
5. **NT entity presence is a hard eligibility gate** — needs a principal decision before any NT grant application.
6. **Defence/sovereignty (Pine Gap, MRF-D, RAAF Darwin) is the highest-value procurement lane**, not a grant.

---

## 9. Sources (fetched and read this session)

- NAIF — naif.gov.au (200): "concessional loans… northern Australia and Australian Indian Ocean Territories"; $7B facility; 01 Jul 2026 "further decade" release; sector list; 30 Jun 2026 performance (35 projects / $4.5B / $33.4B benefit / 18,700 jobs); $3B milestone 22 May 2026; Campus Living Villages Darwin (Feb 2026).
- AMGC AME Fund — amgc.org.au/amef/ (200): $7.5M NT fund; fully committed May 2025; closed.
- CRCNA — crcna.com.au (200): NT + northern WA/QLD coverage; EOI funding calls.
- Source memo — plans/swarm-node-investment-memorandum.md (read in full, 348 lines): $16,245/deployment, $9,811/yr, 1.58yr payback, ~67% margin, 500-node = $8.1M CAPEX, NSW beachhead, IRAP required.
- BLOCKED (Cloudflare/bot-wall): nt.gov.au, business.nt.gov.au, industry.nt.gov.au, dtc.nt.gov.au, invest.nt.gov.au, investmentterritory.nt.gov.au.
