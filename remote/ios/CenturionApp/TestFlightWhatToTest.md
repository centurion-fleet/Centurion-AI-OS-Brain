# Sovereign AI Remote — TestFlight What to Test (build 35)

Marketing version **5.2.142**. Family Beneficiary referrals from You (Settings).

## Fresh install

Delete the previous TestFlight install once before testing if launch assets look stale. After install of **35**, link your Sovereign (LAN QR), then open **You**.

## Family Beneficiary (primary)

1. You → Family Beneficiary Program — nominate a family first name.
2. **Refer a friend or colleague** — try **Choose from Contacts**, or type name + email/phone; attest non-family; **Add to tracker**.
3. Confirm the person appears under **People you’ve referred** as **Waiting**.
4. Pull to refresh (or ↻) — status should stay Waiting until GHL marks them a customer (`centurion-referral-purchased` / `centurion-customer` / `centurion-purchased` on the Brain’s GHL account).
5. **Share list** exports names + Waiting/Customer status.
6. Progress shows **X of 4 customer purchases credited**.

Brain must be on **5.2.141+** with `GHL_API_KEY` + `GHL_LOCATION_ID` in `~/.centurion/.env` for marketing sync + purchase credit.

## Smoke

- Crypto Chat still sends/receives on LAN.
- If Chat from anywhere is enabled, one Away message still works.
