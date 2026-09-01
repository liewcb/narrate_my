const MAX_WIDTH_PX = 1200;
const MAX_FUTURE_SECONDS = 26 * 60 * 60;

Deno.serve(async (req) => {
  try {
    if (req.method !== "GET") {
      return Response.json({ error: "Method not allowed." }, { status: 405 });
    }

    const url = new URL(req.url);
    const resource = url.searchParams.get("resource")?.trim() ?? "";
    const expiresText = url.searchParams.get("expires")?.trim() ?? "";
    const providedSignature = url.searchParams.get("signature")?.trim() ?? "";
    const expires = Number(expiresText);
    const now = Math.floor(Date.now() / 1000);

    if (!isValidPhotoResource(resource)) {
      return Response.json({ error: "Invalid photo resource." }, {
        status: 400,
      });
    }
    if (!Number.isInteger(expires) || expires < now ||
      expires > now + MAX_FUTURE_SECONDS) {
      return Response.json({ error: "Photo link has expired." }, {
        status: 403,
      });
    }

    const signingSecret = requiredEnv("PLACES_PHOTO_SIGNING_SECRET");
    const expectedSignature = await hmacSha256(
      `${resource}|${expires}`,
      signingSecret,
    );
    if (!constantTimeEquals(providedSignature, expectedSignature)) {
      return Response.json({ error: "Invalid photo signature." }, {
        status: 403,
      });
    }

    const apiKey = requiredEnv("GOOGLE_PLACES_API_KEY");
    const googleUrl = new URL(
      `https://places.googleapis.com/v1/${resource}/media`,
    );
    googleUrl.searchParams.set("maxWidthPx", String(MAX_WIDTH_PX));
    googleUrl.searchParams.set("key", apiKey);
    const googleResponse = await fetch(googleUrl, { redirect: "follow" });
    if (!googleResponse.ok || !googleResponse.body) {
      console.error(
        `Google Place Photo failed (${googleResponse.status}):`,
        await googleResponse.text(),
      );
      return Response.json({ error: "Place photo is unavailable." }, {
        status: 502,
      });
    }

    const headers = new Headers();
    headers.set(
      "Content-Type",
      googleResponse.headers.get("Content-Type") ?? "image/jpeg",
    );
    headers.set("Cache-Control", "public, max-age=1800");
    headers.set("X-Content-Type-Options", "nosniff");
    return new Response(googleResponse.body, { status: 200, headers });
  } catch (error) {
    console.error(error);
    return Response.json(
      { error: "Unable to load the place photo." },
      { status: 500 },
    );
  }
});

function isValidPhotoResource(value: string): boolean {
  return /^places\/[A-Za-z0-9_-]+\/photos\/[A-Za-z0-9_-]+$/.test(value);
}

async function hmacSha256(value: string, secret: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(value),
  );
  return bytesToBase64Url(new Uint8Array(signature));
}

function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
}

function constantTimeEquals(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index++) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Required environment variable ${name} is missing.`);
  }
  return value;
}
