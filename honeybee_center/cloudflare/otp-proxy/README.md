# OTP Cloudflare proxy

This Worker is the only public route to the OTP Edge Function. It discards
client-supplied forwarding headers, forwards Cloudflare's connection-derived
`CF-Connecting-IP`, and adds `OTP_PROXY_SHARED_SECRET`. The Edge Function
rejects direct calls without that secret and calls the SQL token-bucket RPC.

Deploy from this directory after setting the same high-entropy
`OTP_PROXY_SHARED_SECRET` in the Supabase Edge Function secret settings:

```powershell
npx wrangler@latest login
npx wrangler@latest secret put OTP_PROXY_SHARED_SECRET
npx wrangler@latest deploy
```

Wrangler prompts for the secret without putting it in a source file. Do not
paste secret values into chat, command arguments, or shell history. The Worker
uses the public fixed Supabase project URL in `wrangler.toml`; no service-role
key is present in this proxy.

After deployment, build the Admin web app with
`--dart-define=OTP_FUNCTION_URL=https://<worker-subdomain>.workers.dev/otp`.
If the Customer app uses OTP recovery, build it with the same URL. Never build
with a service-role key. Worker unit tests run with `npm test`.
