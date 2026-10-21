# ADR-0002: Regulatory findings (verification status, October 2026)
- Status: Accepted (living document; update whenever a primary source is read)
- Date: 2026-10-21
- **Not legal advice.** This records what an engineer could verify from public sources so design choices
  are traceable. Counsel must review before go-live.

## Verification levels
- **Primary**: read the regulator's or statute's own text.
- **Secondary (consistent)**: several independent secondary sources agree, primary not read.
- **Unconfirmed**: could not verify. Must not be relied on as fact.

## Findings

### F1. CBN data localisation circular: **Secondary (consistent); primary located but NOT read**
- Reference **PSS/DIR/PUB/CIR/001/004**, dated **15 June 2026**, issued by the CBN Payments System
  Supervision Department. Its title covers market structure requirements, data localisation, ultimate
  beneficial ownership disclosure and systemic oversight measures.
- Requirement as reported: payment transaction data generated in Nigeria must be **stored and managed in
  Nigeria**, effective **1 January 2027**. Later reporting says the CBN reaffirmed the date, and **no
  extension has been reported** (as of 2026-10-21).
- Addressees as reported: deposit money banks, microfinance banks, mobile money operators, switching
  companies, PTSPs, PSSPs, super agents and other licensed payment operators.
- **Unconfirmed / unclear:**
  - The circular reportedly does **not define** "payment transaction data". Mondaq's commentary (read)
    explicitly calls its broader list (payer/beneficiary details, amounts, references, auth records, routing,
    logs) the author's interpretation.
  - Whether **KYC data** is covered: **not addressed** in any source read.
  - Whether **backups/DR copies abroad** are allowed: not stated. Commentary reads it as requiring backups
    in Nigeria.
  - Whether **non-licensed platforms** like us are directly in scope: not stated.
- Why primary wasn't read: the cbn.gov.ng PDF returned HTTP 403 to automated fetch, and in a browser it
  showed a bot-verification challenge. We do not bypass bot checks. **Action:** a human downloads the PDF
  into `docs/regulatory/` and this finding is re-checked.
- Design consequence: [ADR-0001](0001-hosting-and-data-residency.md) treats our ledger as in scope (no real
  payment data offshore, Nigeria-hosted production).

### F2. NDPA 2023 + GAID are the operative regime: **Secondary (consistent)**
- The GAID (General Application and Implementation Directive) under the NDPA was adopted 20 March 2025 and
  took effect **19 September 2025**. Sources report that it displaces the NDPR 2019 and its 2020
  Implementation Framework.
- GAID **retention specifics: Unconfirmed** (not found in any source read).

### F3. NDPA principles: **Primary (Act text read)**
- s.24(1)(c): personal data must be "limited to the minimum necessary" for its purpose.
- s.24(1)(d): personal data must be "retained for not longer than is necessary" for its lawful basis.
- s.65 defines **sensitive personal data** to include genetic and **biometric data** used to uniquely
  identify a person, plus health, religion, ethnicity, political opinion and others. BVN/NIN numbers are
  **not** listed as sensitive per se, but they are identifiers we have no need to hold.
- s.41: transfer of personal data out of Nigeria needs adequate protection or another lawful basis (s.43).
- Design consequences: store KYC as **status + provider reference + salted hash** only. Never store raw
  BVN/NIN. **Never store biometrics or liveness selfies.** Minimise faces in e-POD photos. Location is
  collected only at business events (visit, delivery), not tracked continuously. A retention schedule
  (TBD, Phase 6) is required per data class.

### F4. CBN instant-payment security rules: **Secondary (consistent)**
- Circular reported as **"Additional Functionalities for Instant Payment"**, dated **12 March 2026**,
  effective **1 July 2026**, addressed to banks, OFIs and PSPs.
- Reported measures: MFA-protected opt-in/opt-out of instant payments, single active device per mobile
  banking app, a ₦20,000 inflow/outflow cap in the first 24h after app activation, liveness + real-time
  BVN/NIN validation for new/reactivated accounts. Sources differ on which parts took effect in May vs July.
- Applies to our **partners**, not to us directly. Design consequence: don't undermine them. Our app never
  initiates transfers out of customer bank accounts. Inflows arrive by customer-initiated transfer into
  partner virtual accounts. Any partner-side limits or holds surface as provider statuses, never overridden.

### F5. CBN automated AML baseline standards: **Secondary (consistent)**
- "Baseline Standards for Automated Anti-Money Laundering (AML) Solutions", dated **10 March 2026**.
  Roadmaps were due within 3 months (~10 June 2026). Full compliance is reported as 18 months for deposit
  money banks and 24 months for OFIs/PSPs. Those end dates are our arithmetic from the reported durations.
- Applies to licensed institutions (our partners). Design consequence: we pass partner-required payer
  metadata through unchanged, keep a complete immutable money ledger, and can produce per-customer
  statements on request. We do **not** run our own AML scoring.

### F6. CBN three-tier KYC: **Unconfirmed for 2026**
- Long-standing regime, but current tier limits are **still unverified** after the Phase 3 search
  (2026-10-21). Vendor sources disagree: youverify.co pages give Tier 1 as ₦30,000 daily / ₦300,000 balance
  in one place and ₦50,000 / ₦300,000 in another, and Tier 2 as ₦200,000 or ₦500,000 daily. An older
  businessday.ng report gives different figures again. The CBN circular wasn't found. **Decision:** no tier
  limits in code. ADR-0005 defines a coarse `kyc_level` (0/1/2) that business rules reference through
  configuration.
  Sources (search summaries only): https://youverify.co/blog/cbn-kyc-aml-requirements-2026,
  https://youverify.co/blog/3-tiered-know-your-client-kyc-requirements, https://businessday.ng/?p=145802

### F7. Data-centre / sovereign-cloud landscape: **Secondary**
- NITDA reportedly signed instruments for a **National Sovereign Cloud Initiative** on 4 August 2026, with
  a provider certification platform from October 2026 and a public register to follow.
- Local providers (e.g. Clouds2Africa, Open Access Data Centres) publicly claim readiness. No managed
  PostgreSQL offering was confirmed.

## Platform-wide consequences (binding)
1. The platform **never custodies funds**. The wallet is a ledger mirror of partner-held virtual accounts.
2. KYC = status + provider reference + hash. No raw BVN/NIN, no biometrics.
3. No real payment transaction data outside Nigeria (ADR-0001).
4. Every claim above stays at its verification level. "Reportedly" does not become fact without a primary read.

## Sources (accessed 2026-10-21)
| Source | Used for | Access |
|---|---|---|
| https://www.cbn.gov.ng/Out/2026/CCD/CIRCULAR%20ON%20INTRODUCTION%20OF%20MARKET%20STRUCTURE%20REQUIREMENTS,%20DATA%20LOCALISATION,%20ULTIMATE%20BENEFICIAL%20OWNERSHIP%20DISCLOSURE,%20AND%20SYSTEMIC%20OVERSIGHT%20MEASURES%20IN%20THE%20NIGERIA%20PAYMENTS%20SYSTEM.pdf | F1 primary | **not read** (403 / bot challenge) |
| https://www.mondaq.com/nigeria/financial-services/1812264/cbns-data-localisation-directive-compliance-considerations-for-payment-system-participants | F1 | read in full |
| https://goenebeli.com/cbn-circular-pss-dir-pub-cir-001-004-15-june-2026new-rules-on-data-localisation-beneficial-ownership-disclosure-market-concentration-in-the-nigerian-digital-payments-ecosystem/ | F1 (reference no.) | search summary only (fetch HTTP 500) |
| https://guardian.ng/business-services/cbn-commits-to-data-localisation-insists-on-january-deadline/ | F1 (deadline reaffirmed) | search summary only (fetch HTTP 403) |
| https://msmeafricaonline.com/cbn-orders-banks-fintechs-to-store-payment-data-in-nigeria-from-2027/ | F1 | search summary only |
| https://thetrumpet.ng/cbn-insists-on-january-1-2027-deadline-for-banks-fintechs-to-store-payment-data-in-nigeria/ | F1 | search summary only |
| https://www.mondaq.com/nigeria/data-protection/1666780/nigeria-data-privacy-law-2025-ndpa-gaid-guide | F2 | search summary only |
| https://blog.lawpavilion.com/ndp-act-2023-gaid-2025-a-comprehensive-guide-to-nigerias-new-data-protection-landscape | F2 | search summary only |
| https://digitalpolicyalert.org/change/13270 | F2 (adoption date) | search summary only |
| https://www.dataguidance.com/sites/default/files/data_protection_act_2023.pdf | F3 (Act text) | **read (text extracted)** |
| https://www.aluko-oyebode.com/insights/cbn-new-instant-payment-security-requirements/ | F4 | search summary only |
| https://www.afriwise.com/blog/device-binding-and-transaction-caps-the-cbns-instant-payment-guidelines-take-effect | F4 | search summary only |
| https://www.legit.ng/business-economy/money/1710605-8-cbn-rules-bvn-mobile-app-payments-starting-july-1/ | F4 | search summary only |
| https://businessday.ng/news/article/banks-fintechs-face-new-cbn-deadline-for-automated-aml-systems/ | F5 | search summary only |
| https://leadership.ng/cbn-orders-banks-to-comply-with-anti-money-laundering-solutions-in-18-months/ | F5 | search summary only |
| https://youverify.co/en/blogs/cbn-kyc-aml-requirements-2026 | F5 | search summary only (vendor) |
| https://techeconomy.ng/nigeria-data-localisation-cloud-economy | F7 | search summary only |
| https://guardian.ng/business-services/tech-sector-optimistic-about-2027-data-localisation-deadline/ | F7 | search summary only |
