# xray on Cloady (USE1 free tier)

VLESS + WS + TLS, container listens on 3000, Cloady terminates TLS on 443.
Traffic cap: 190GB/month via entrypoint.sh, resets on the 1st (UTC).

Set in Cloady env vars (do NOT commit secrets):
- `XRAY_UUID` — VLESS UUID
- `WS_PATH` — e.g. `/a46bdb42`
- `PORT=3000`
