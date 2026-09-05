// verify-captcha — server-side hCaptcha verification for Module 5's
// 5-failed-OTP gate (REQ_501_12 / REQ_502_21).
//
// WHY THIS EXISTS: hCaptcha is only meaningful if the solve is checked by
// something the user cannot edit. The check needs the account's SECRET key,
// and a secret shipped inside a Flutter app is not a secret — anyone can
// pull it out of the APK. So the app sends only the token it got from the
// widget, and this function (which holds the secret as an Edge Function
// env var) asks hCaptcha whether that token is genuine.
//
// DEPLOY (see the chat for the walkthrough):
//   supabase secrets set HCAPTCHA_SECRET=0x0000000000000000000000000000000000000000
//   supabase functions deploy verify-captcha
//
// That secret is hCaptcha's official TEST secret, which pairs with the test
// sitekey in `AppConfig.hcaptchaSiteKey`. The pair always verifies
// successfully, so the whole loop is demonstrable without registering an
// hCaptcha account. Swap BOTH together when you go live — a real sitekey
// verified against the test secret fails, and vice versa.

const HCAPTCHA_SECRET = Deno.env.get("HCAPTCHA_SECRET") ?? "";
const SITEVERIFY_URL = "https://api.hcaptcha.com/siteverify";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") {
    return json({ success: false, error: "method_not_allowed" }, 405);
  }

  // The adapter treats any non-`success: true` body as a failed solve, so
  // every early return below still has to carry `success: false` rather
  // than relying on the status code alone.
  if (!HCAPTCHA_SECRET) {
    console.error("HCAPTCHA_SECRET is not set — run: supabase secrets set HCAPTCHA_SECRET=...");
    return json({ success: false, error: "secret_not_configured" }, 500);
  }

  let token = "";
  try {
    const body = await req.json();
    token = typeof body?.token === "string" ? body.token : "";
  } catch (_) {
    return json({ success: false, error: "invalid_json" }, 400);
  }
  if (!token) return json({ success: false, error: "missing_token" }, 400);

  try {
    const res = await fetch(SITEVERIFY_URL, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ secret: HCAPTCHA_SECRET, response: token }),
    });
    const data = await res.json();
    // hCaptcha returns { success: bool, "error-codes": [...] }. Pass the
    // codes through so a failure is diagnosable from the Flutter logs
    // (`sitekey-secret-mismatch` is the one to expect if only one half of
    // the test pair was swapped).
    return json({
      success: data?.success === true,
      errors: data?.["error-codes"] ?? [],
    });
  } catch (err) {
    console.error("siteverify call failed", err);
    return json({ success: false, error: "siteverify_unreachable" }, 502);
  }
});
