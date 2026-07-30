# Centurion — Sovereign AI Infrastructure for the Next Cycle

**Confidential Investment Memorandum**
27 July 2026
Prepared for Sophisticated Institutional Investors
Not for Distribution

**Contact:** Steve White — SW@mastermindalliance.com.au

---

## Table of Contents

1. Executive Summary
2. The Three Structural Crises in AI Infrastructure
3. The Centurion Solution — Two-Box Sovereign Architecture
4. Business Model & Commercial Structure
5. Market Analysis — SOM / SAM / TAM
6. Unit Economics
7. Financial Projections & Exit Pathways
8. Capital Raise Strategy
9. Risk Assessment & Mitigation
10. Conclusion & Strategic Imperative

---

## 1. Executive Summary

### 1.1 The Opportunity

Australia faces a structural shortage of sovereign AI compute capacity that will deepen over the next decade. The nation's defence, intelligence, and civil service agencies depend on GPU-accelerated compute for everything from wargaming and signal processing to large language model inference and real-time sensor fusion. Yet the current supply chain—rented hyperscaler instances, bespoke government data centre contracts, and ad hoc academic allocations—delivers neither the cost profile, the security posture, nor the scalability that sovereign requirements demand.

Centurion has been formed to address this gap with a fundamentally different architecture: a distributed, dual-benefit compute node purpose-built for government deployment.

The company's innovation is architectural. Rather than concentrating compute in monolithic data centres, Centurion disperses it across government facilities using a paired deployment: a **Swarm node**—an MSI workstation housing four NVIDIA RTX 4090 GPUs (~$12,000 per node)—and up to five **Jetson Orin NX 16GB edge AI agents** (~$699 each, one per senior executive). The combined two-box deployment costs approximately **$16,245 per government site**, inclusive of five agents and one Swarm node. This is not a server. It is an appliance: deployable in hours, serviceable by existing facilities staff, and auditable under sovereign security protocols without third-party access.

The business model is equally distinctive. Centurion sells **GPU-hours to government under a take-or-pay structure** modelled on the gym membership: the government commits to a **70% utilisation floor**, paying for 6,132 GPU-hours per year per GPU whether they consume them or not. Centurion retains the right to sell the unused 30% on the secondary spot market (primarily Vast.ai and equivalent platforms), with the government receiving a **50% feed-in tariff** on those idle-cycle sales. When the government needs more than its 70% allocation, overflow capacity is available at **$0.40 per GPU-hour**—the same wholesale rate underwritten by the NSW Government.

This creates an elegant structural analogy: the GPUs are solar panels on a government roof, generating compute 24 hours a day. Government consumption takes priority as self-consumption. Idle cycles flow to the grid—in this case, the Vast.ai spot market—and surplus revenue is shared. The government receives the benefit of subsidised overflow compute when demand spikes.

The **retention mechanic** is equally deliberate. Each Swarm node is paired with five Jetson edge agents, each deployed as a personal AI assistant for a senior government executive. The value proposition is simple: keep the Swarm plugged in, and the agents are free. Disconnect the Swarm, and those agents—by now embedded in daily workflow, decision support, and classified analysis—are lost. The agents are not a revenue line; they are a **retention device**.

### 1.2 Unit Economics

A single deployment of one Swarm node (4 × RTX 4090) plus five Jetson agents requires **$16,245 in upfront CAPEX**. At the base wholesale rate of **$0.40 per GPU-hour**, with a **70% take-or-pay commitment**, each node generates **24,528 billable GPU-hours per year** (6,132 per GPU × 4 GPUs). **Annual revenue per deployed node: $9,811.**

- **Capital payback:** 1.58 years
- **Breakeven GPU-hour cost** (straight-line amortisation over 5 years): $0.132/hr
- **Margin per GPU-hour beyond breakeven:** $0.268
- **Unit-level gross margin at $0.40/hr:** ~67%

**Two commercial structures:**
- **Option A (70% take-or-pay):** Government commits 70% floor, receives 50% feed-in tariff on idle-capacity sales. Centurion operates spot-market resale.
- **Option B (100% exclusive retainer):** Government commits 100% utilisation at 20% discount ($0.32/GPU-hr). No resale of idle capacity. Purely bilateral.

### 1.3 Fleet Economics and Scale

- **Seed round:** 500 nodes deployed
- **Hardware CAPEX at 500 nodes:** $8.1M
- **Total seed raise:** ~$8–10M (hardware, IRAP certification, software platform, working capital)
- **Annualised revenue at 500 nodes:** $4.9M
- **Seed pre-money valuation:** $25–30M (~22–25% dilution)
- **Series A trigger:** 10,000 nodes
- **Primary exit range:** 100,000–150,000 nodes (projected 2030–2032)
- **Revenue at 100-150K nodes:** ~$1.0–1.5B/yr at $0.40/GPU-hr
- **Terminal TAM (upper bound):** ~850,000 deployable sites by 2037
- **Terminal annual revenue:** $8.3B
- **Terminal EBITDA:** ~$7.9B (~95% margin)

The margin structure reflects minimal ongoing COGS once nodes are deployed: electricity, network backhaul, occasional hardware refresh, and field maintenance—no data centre lease, no cloud provider margin, no hyperscaler uplift.

### 1.4 Exit Scenarios

| Scenario | Node Count | Timeline | Valuation |
|----------|-----------|----------|-----------|
| **Primary — Strategic Acquisition** | 100,000–150,000 | 2028–2030 | $2–5B |
| **Secondary — Defence Prime Acquisition** | Any | Accelerated | $3–8B |
| **Tertiary — IPO** | 250,000+ | Post-2030 | $6–10B market cap |

### 1.5 Seed Round Summary

Raising **$8–10M** in equity seed at **$25–30M pre-money** (22–25% dilution):

| Allocation | Amount |
|-----------|--------|
| Hardware procurement (500 Swarm nodes + Jetson agents) | $8.1M |
| IRAP certification | $0.5–0.8M |
| Software platform development | $0.5–0.7M |
| Working capital & initial OpEx | $0.5–1.0M |

### 1.6 Key Corrections to Prior Material

- $18.5M government savings → corrected to **$7.65M**
- $18.2M revenue for 1,280-pod → corrected to **$2.16M**
- $1.88M margin → corrected to **$1.56M**
- 850,000 nodes → correctly characterised as **upper-bound TAM**, not exit trigger
- GPU-hour pricing revised from $0.25 to **$0.40** (NSW Government wholesale rate)
- Jetson agent monthly subscription ($450) → **eliminated** (agent is retention device, not revenue line)

### 1.7 The Investment Case

At $16,245 per deployment and a 1.58-year payback, Centurion achieves capital intensity that traditional data centre operators cannot approach. A hyperscaler GPU cluster costs $30,000–$50,000 per GPU in TCO. Centurion's per-GPU capital cost is ~$3,000. The implication: Centurion can underprice incumbents while earning margins that would be the envy of any infrastructure asset.

---

## 2. The Three Structural Crises in AI Infrastructure

### 2.1 Crisis I: The Hyperscale Brick Wall — Capital Has Become the Enemy of Deployment

- A single hyperscale AI data centre now requires **$2B+** upfront capital
- Construction timelines: **3–5 years** from site selection to commissioning
- Microsoft FY2025: **$80B** data centre capex. Amazon: **$100B**. Google: **$75B**
- An AI-scale data centre demands **50–200 MW** of dedicated grid capacity = a mid-sized regional city
- Grid connection queues: **5–10 years** in constrained jurisdictions
- ~**$64B** in AI data centre projects currently blocked in development pipelines globally

For sovereign/government customers: a hyperscale facility in Virginia, Dublin, or Singapore does not satisfy Australian data sovereignty requirements.

### 2.2 Crisis II: The GPU Debt Trap

- CoreWeave (March 2025 IPO): **$24.9B total debt** vs ~$2.8B equity = **894% debt-to-equity ratio**
- Entire asset base = depreciating NVIDIA H100 GPUs with technology refresh cycles measured in months
- Largest customer (Microsoft) represents **60%+ of revenue** and is simultaneously building competing capacity
- **H100 rental rates collapsed** from $8.00/hr (early 2024) to ~$3.00/hr (mid-2025) = **62.5% decline in 18 months**

Centurion's immunity: a four-GPU Swarm node costs $12,000. No leverage. No $24.9B balance sheet at risk. Each deployment is a discrete, recoverable capital unit.

### 2.3 Crisis III: Silicon Obsolescence

- NVIDIA's 12-month architecture release cycle: each new generation delivers 2–4x inference throughput per dollar
- Productive life of a top-tier GPU in competitive rental: **2–3 years**
- These 2–3 year assets are being financed with 20–30 year infrastructure-style bonds
- **Stranded asset risk** is a live scenario being modelled by credit teams

Centurion's advantage: each Swarm node is a discrete $12,000 unit, not a $2B monolithic facility. The network can be incrementally refreshed as GPU generations turn.

---

## 3. The Centurion Solution — Two-Box Sovereign Architecture

### 3.1 The Distributed Supercomputer

No new construction. No grid interconnection. No foreign jurisdiction.

**Architecture:** Paired two-box design per deployment site:
- **Swarm node:** MSI workstation, 4× NVIDIA RTX 4090, 128GB RAM, NVMe storage, enterprise power conditioning
- **Jetson agents:** Up to 5 × Orin NX 16GB edge modules (personal AI assistants for senior executives)
- **Total cost:** ~$16,245
- **Installation:** Under 4 hours by existing facilities staff

Compared to hyperscale: no $500M–$2B construction capital, no 18–36 month build timeline, no dedicated grid interconnection. The "data centre" is the government facility it already occupies.

### 3.2 The Sovereign AI Layer

- Centurion operates and continuously improves its own LLM stack across the distributed node network
- As the network scales, effective cost per inference operation declines along a steep experience curve
- Fixed orchestration overhead amortised across exponentially larger compute base
- Meanwhile, contracted price per GPU-hour is locked under take-or-pay
- The spread between cost and price widens → gross margins expand automatically with scale
- **Sovereign AI imperative:** Australian-trained, Australian-hosted, Australian-governed models

### 3.3 The Retention Mechanic: Jetson Agents

Each Swarm node is paired with up to five Jetson edge agents, deployed as personal AI assistants for senior government executives. The agent learns from their workflow, observes their decisions, and builds a private model of their domain expertise. **This model never leaves the pod.** The executive's proprietary knowledge is not uploaded to a cloud. It is sovereign in the most literal sense.

When that executive leaves (resignation, retirement, reorganisation): **the agent stays.** Every draft, every decision pattern, every domain insight stays with the institution. The knowledge walks out with no one.

Commercial structure: "Keep the Swarm plugged in, get the agents free." The agents are not a revenue line. They are a retention device that increases in value with every month of use.

---

## 4. Business Model & Commercial Structure

### 4.1 The Take-or-Pay Foundation

**Option A: The Gym Membership (70% Take-or-Pay)**
- Government commits to 6,132 GPU-hours/GPU/year at $0.40/hr
- = 70% uptime of 4 GPUs = 24,528 GPU-hours/deployment/year
- Centurion sells idle 30% on Vast.ai spot market
- Government receives **50% feed-in tariff** on all resale revenue
- Overflow beyond 70% at $0.40/hr — no penalty, no renegotiation

**Option B: The Personal Trainer (100% Exclusive)**
- Government commits to 8,760 GPU-hours/GPU/year at 20% discount ($0.32/hr)
- GPUs are exclusively theirs. Centurion sells zero spare capacity
- Designed for Defence, intelligence agencies, critical infrastructure operators

### 4.2 The Solar Analogy

The four RTX 4090 GPUs are solar panels on a government roof. Government consumption takes priority (self-consumption). Idle cycles flow to the grid (Vast.ai spot market). Government receives a feed-in tariff (50% of spot revenue) credited against their GPU-hour bill. When demand spikes, they draw overflow at $0.40/hr (equivalent to drawing from the grid after dark).

### 4.3 Three Ownership Structures

| Model | Description | Best For |
|-------|-------------|----------|
| **A: Centurion Acquisition** | Centurion buys hardware, retains 100% compute revenue | Seed round, proving the model |
| **B: Government Procurement** | Agencies buy hardware via ICT budgets, Centurion provides software | Long-term, post-accreditation |
| **C: Infrastructure Fund** | Fund acquires hardware, Centurion gets ~85% of economics | Scale (recommended) |

---

## 5. Market Analysis — SOM / SAM / TAM

### 5.1 SOM: NSW Government Beachhead

Three independent data points confirm NSW is not a speculative buyer:

1. **AI Scribe Deployment — $38.7M confirmed budget:** NSW Health ~6,000 clinicians. 500 nodes sufficient to service meaningful portion at $0.40/GPU-hr = ~$4.9M/yr compute revenue.
2. **$17.7M Data Centre Investment Fund:** Explicit government preference for compute infrastructure outside hyperscaler dependency.
3. **Whole-of-Government AI Assessment Framework:** Mandatory procurement pathway that advantages Centurion's structurally compliant architecture.

**SOM sizing:** ~$38M/yr total addressable within NSW at sovereign pricing.

### 5.2 SAM: $1.2B/yr

Australian public sector: 1.65M FTEs across federal, state, territory jurisdictions. Government cloud expenditure: ~$9.3B/yr across all jurisdictions. AI compute sub-category: ~$1.2B/yr in explicit budget allocation, growing at 28% CAGR.

Beyond government: healthcare (Privacy Act data residency), financial services (APRA CPS 234), legal/professional services.

### 5.3 TAM: $120B+ global mid-range distributed compute by 2030

Three converging markets:
- Sovereign cloud compute: $35B+ by 2030 (EU AI Act, Australia sovereign frameworks, Japan Government Cloud, SE Asia, Middle East)
- Mid-range inference compute: $50B+ by 2030 (80% of enterprise AI workloads)
- Distributed edge compute: $35B+ by 2030 (sovereign workloads requiring in-country data)

---

## 6. Unit Economics

### 6.1 The Fundamental Insight: Zero Electricity Cost

In every conventional data centre or cloud compute business, power is the single largest operating expense (40-60% of gross revenue). **Centurion eliminates this cost entirely** at the platform level. Pod hosts (government facilities) already pay for power in buildings they already occupy. The incremental draw of a Swarm node (~800W under load) is absorbed into existing facility budgets.

This is a genuine structural advantage that permanently separates Centurion's margin profile from every centralised competitor.

### 6.2 Key Metrics

| Metric | Value |
|--------|-------|
| Per-deployment CAPEX (1 Swarm + 5 Jetson) | $16,245 |
| Billable GPU-hours/yr per deployment (70% ToP) | 24,528 |
| Annual revenue per deployment | $9,811 |
| Capital payback period | 1.58 years |
| Breakeven GPU-hr cost (5yr straight-line) | $0.132/hr |
| Margin per GPU-hr at $0.40 | $0.268 |
| Unit-level gross margin | ~67% |
| Per-GPU capital cost | ~$3,000 |
| Hyperscaler per-GPU TCO (comparison) | $30,000–$50,000 |

---

## 7. Financial Projections & Exit Pathways

### 7.1 Deployment Trajectory

| Phase | Year | Nodes | Annual Revenue | EBITDA | EBITDA Margin |
|-------|------|-------|---------------|--------|---------------|
| Seed Pilot | 2027–2028 | 500 | ~$4.9M | — | — |
| Series A Trigger | 2028 | 10,000 | ~$98M | ~$88M | ~90% |
| Growth | 2030 | 100,000 | ~$981M | ~$932M | ~95% |
| Terminal TAM | 2037 | 850,000 | ~$8.3B | ~$7.9B | ~95% |

### 7.2 Exit Scenario Analysis

| Scenario | Nodes | Timeline | Valuation | Multiple on Seed |
|----------|-------|----------|-----------|-----------------|
| Strategic acquisition | 100K–150K | 2028–2030 | $2–5B | 67–200x |
| Defence prime acquisition | Any | Accelerated | $3–8B | 100–320x |
| IPO | 250K+ | Post-2030 | $6–10B | 200–400x |

---

## 8. Capital Raise Strategy

### 8.1 Seed Round

- **Amount:** $8–10M
- **Pre-money valuation:** $25–30M
- **Dilution:** 22–25%
- **Structure:** Equity

### 8.2 Pre-Money Valuation Justification

Three independent frameworks:

1. **Comparable Transactions:** CoreWeave raised Series A at $2B+ pre-revenue. Lambda Labs $320M at $1.5B in 2023. Centurion at $25–30M represents a 99% discount with structurally superior unit economics.

2. **Terminal Value Discount:** At 850K nodes = $7.9B/yr EBITDA. At 15x multiple (discount to infrastructure peers at 18–24x) = $118B+ terminal EV. Seed entry against $2–5B exit = 67–200x return.

3. **Revenue Multiple on Pilot:** 500-node pilot = $4.9M annualised revenue. $25–30M pre-money = 5.1–6.1x forward revenue multiple on pilot year.

### 8.3 Series A Triggers (H2 2028, $40–60M at $150–250M pre)

1. 500 nodes deployed with 70%+ ToP utilisation over 90 consecutive days
2. IRAP Protected certification received or materially advanced
3. Minimum one signed government contract for sovereign AI compute services
4. Feed-in tariff mechanism operational with confirmed spot market revenue
5. Pipeline of $100M+ in qualified government procurement opportunities

---

## 9. Risk Assessment & Mitigation

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| IRAP certification slippage | Medium (40%) | Critical | Engage assessors Month 1. Design to ISM controls from inception. Pursue interim IRAP Unclassified. 25% contingency budget. |
| GPU supply chain constraints | Medium (35%) | Significant | 10% buffer inventory. Direct MSI distributor relationship. RTX 5090 fallback. Volume pricing at seed close. |
| Jetson pricing volatility | Medium (30%) | Moderate | Lock pricing at seed close. Model sensitivity at $999/module. Orin NX 8GB fallback. |
| Spot market dependency | Medium (30%) | Moderate | Feed-in is upside, not dependency. Base economics work without it. Diversify across Vast.ai, RunPod, TensorDock. |
| Government procurement timeline | Medium (40%) | Significant | Pre-position 50 demo nodes. Use NSW AI Assessment Framework to fast-track. Conditional commencement clause. |

Post-mitigation: no risk assessed as both High probability and Critical impact.

---

## 10. Conclusion & Strategic Imperative

The window to establish a sovereign distributed compute position ahead of the next wave of government AI procurement mandates is measured in **quarters, not years.**

**Centurion presents:**
- Hard asset backing (physical GPU nodes)
- Contractual revenue (take-or-pay with government)
- Capital efficiency ($3,000/GPU vs $30K–$50K hyperscaler)
- Structural immunity to GPU debt trap and obsolescence cycles
- Retention moat (Jetson agents increase switching cost with every month of use)
- Terminal exit pathway: $2–5B strategic acquisition

At $25–30M pre-money against a $2–5B strategic exit, the asymmetry defines the opportunity.

**The defining infrastructure trade of the decade. At a fraction of the capital cost.**

---

*— End of Memorandum —*

---

## Appendix: Market Reports Referenced

- S&P: Decoding Data Center Risk: Multi-Dimensional Analysis, July 1, 2026
- S&P: From Growth to Growing Risk, Jan 21, 2026
- S&P: AI Infrastructure Buildout Weighs Credit Risks and Rewards, Jan 21, 2026
- S&P: Where Are AI Investment Risks Hiding?, Jan 21, 2026
- Australia Data Center Market Report (multiple sources)
- Grid Strategies LLC: $64B in AI data centre projects blocked in development pipelines
- CoreWeave March 2025 IPO filing
- CNX Software: NVIDIA Jetson module pricing increase up to 101%, 21 July 2026
