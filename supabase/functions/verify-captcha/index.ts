// NarrateMy — Module 5 (User Profile & Language Management)
// Supabase Edge Function: verify-captcha
//
// UC400 A8 / REQ_501_12 / REQ_502_21: after 5 consecutive failed OTP
// attempts, the OTP screen shows an hCaptcha challenge (see
// `lib/core/widgets/hcaptcha_widget.dart`). This function is what actually
// checks a solve is real — hCaptcha's SECRET key lives only here (as a
// Supabase secret, never in the Flutter app) and calls hCaptcha's own
// server-to-server `siteverify` endpoint.
//
// Deploy:
//   supabase functions deploy verify-captcha
//
// Set the secret first (one-time, from your hCaptcha dashboard's site
// "Secret key" — https://dashboard.hcaptcha.com):
//   supabase secrets set HCAPTCHA_SECRET=your_secret_key_here
//
// Called from Dart via `AuthRemoteDataSource.verifyCaptcha` →
// `_client.functions.invoke('verify-captcha', body: {'token': token})` —
// supabase_flutter automatically attaches the project's anon key, which
// satisfies this function's default JWT verification (no
// `--no-verify-jwt` flag needed on deploy).

// deno-lint-ignore-file no-explicit-any
import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';

const HCAPTCHA_SECRET = Deno.env.get('HCAPTCHA_SECRET');
const HCAPTCHA_VERIFY_URL = 'https://hcaptcha.com/siteverify';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

serve(async (req: Request) => {
  // Browser-originated calls (e.g. testing this function from a web
  // client) preflight with OPTIONS — native Flutter calls via
  // supabase_flutter typically don't, but this costs nothing to handle.
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  if (req.method !== 'POST') {
    return jsonResponse({ success: false, error: 'method_not_allowed' }, 405);
  }

  if (!HCAPTCHA_SECRET) {
    // Misconfiguration, not the tourist's fault — surfaced as a plain
    // ServerFailure by SupabaseAuthRepositoryAdapter.verifyCaptcha, not a
    // "wrong CAPTCHA" message.
    return jsonResponse({ success: false, error: 'server_not_configured' }, 500);
  }

  let token: unknown;
  try {
    const body = await req.json();
    token = body?.token;
  } catch (_error) {
    return jsonResponse({ success: false, error: 'invalid_request_body' }, 400);
  }

  if (typeof token !== 'string' || token.length === 0) {
    return jsonResponse({ success: false, error: 'missing_token' }, 400);
  }

  try {
    const verifyResponse = await fetch(HCAPTCHA_VERIFY_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        secret: HCAPTCHA_SECRET,
        response: token,
      }),
    });

    const result: any = await verifyResponse.json();
    return jsonResponse({ success: result?.success === true });
  } catch (_error) {
    return jsonResponse({ success: false, error: 'upstream_verification_failed' }, 502);
  }
});
