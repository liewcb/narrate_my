import { createClient } from "npm:@supabase/supabase-js@2";

// This project does not currently generate Supabase Database TypeScript
// definitions. Keep the admin client untyped at this boundary; every value
// read from PostgREST is explicitly normalised before it enters domain logic.
type SupabaseAdminClient = any;

const PRIMARY_MODEL = Deno.env.get("GEMINI_RECOMMENDATION_MODEL") ??
  "gemini-3.5-flash-lite";
const FALLBACK_MODEL = Deno.env.get("GEMINI_RECOMMENDATION_FALLBACK_MODEL") ??
  "gemini-3.6-flash";
const PROMPT_VERSION = "nearby-v2-preference-cache";
const DEFAULT_RADIUS_KM = 10;
const CACHE_TTL_HOURS = numberFromEnv("RECOMMENDATION_CACHE_TTL_HOURS", 24);
const CACHE_STALE_DAYS = numberFromEnv("RECOMMENDATION_CACHE_STALE_DAYS", 7);
const DAILY_CALL_BUDGET = numberFromEnv("GEMINI_DAILY_CALL_BUDGET", 15);

interface Preferences {
  attraction_interests: string[];
  food_cuisine_interests: string[];
  dietary_preferences: string[];
  accessibility_preferences: string[];
  category_exclusions: string[];
  dietary_restrictions: string[];
}

interface RecommendationItem {
  name: string;
  category: string;
  address: string | null;
  reason: string;
  rank: number;
}

interface CacheRecord {
  recommendations: unknown;
  model_name: string;
  created_at: string;
  expires_at: string;
}

const DEFAULT_PREFERENCES: Preferences = {
  attraction_interests: [],
  food_cuisine_interests: [],
  dietary_preferences: [],
  accessibility_preferences: [],
  category_exclusions: [],
  dietary_restrictions: [],
};

Deno.serve(async (req) => {
  const startTime = Date.now();

  try {
    if (req.method !== "POST") {
      return Response.json({ error: "Method not allowed." }, { status: 405 });
    }

    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    const geminiApiKey = requiredEnv("GEMINI_RECOMMENDATION_API_KEY");
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const body = await req.json();
    const latitude = Number(body.latitude);
    const longitude = Number(body.longitude);
    const radiusKm = clamp(
      body.radius_km == null ? DEFAULT_RADIUS_KM : Number(body.radius_km),
      1,
      50,
    );

    if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90) {
      return Response.json({ error: "Invalid latitude." }, { status: 400 });
    }
    if (!Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
      return Response.json({ error: "Invalid longitude." }, { status: 400 });
    }
    if (!Number.isFinite(radiusKm)) {
      return Response.json({ error: "Invalid radius." }, { status: 400 });
    }

    // The Flutter Supabase client forwards the existing login-session JWT.
    // A valid user is personalised; a guest keeps the default preferences.
    const userId = await currentUserId(
      supabase,
      req.headers.get("Authorization"),
    );
    const { preferences, usedDefaultPreferences } = await loadPreferences(
      supabase,
      userId,
    );

    const preferenceHash = await sha256(stablePreferences(preferences));
    const latitudeBucket = bucket(latitude);
    const longitudeBucket = bucket(longitude);
    const cacheKey = await sha256(
      [
        PROMPT_VERSION,
        latitudeBucket,
        longitudeBucket,
        radiusKm.toFixed(2),
        preferenceHash,
      ].join("|"),
    );

    const { data: cacheData, error: cacheError } = await supabase
      .from("nearby_recommendation_cache")
      .select("recommendations, model_name, created_at, expires_at")
      .eq("cache_key", cacheKey)
      .maybeSingle();
    if (cacheError) throw cacheError;

    const cached = cacheData as CacheRecord | null;
    const cachedRecommendations = validateRecommendations(
      cached?.recommendations,
    );
    const now = Date.now();
    if (
      cached &&
      cachedRecommendations.length > 0 &&
      Date.parse(cached.expires_at) > now
    ) {
      return recommendationResponse(cachedRecommendations, {
        source: "supabase_cache",
        modelName: cached.model_name,
        cachedAt: cached.created_at,
        radiusKm,
        usedDefaultPreferences,
      });
    }

    // Bootstrap the new cache from a compatible successful log. This avoids
    // spending a Gemini request immediately after deployment and lets an
    // already rate-limited project continue serving recent recommendations.
    const loggedRecommendations = await findCompatibleRecommendationLog({
      supabase,
      userId,
      latitude,
      longitude,
      preferences,
    });
    if (loggedRecommendations) {
      await saveCache({
        supabase,
        cacheKey,
        latitudeBucket,
        longitudeBucket,
        radiusKm,
        preferenceHash,
        recommendations: loggedRecommendations.recommendations,
        modelName: loggedRecommendations.modelName,
      });
      return recommendationResponse(loggedRecommendations.recommendations, {
        source: "recommendation_log_cache",
        modelName: loggedRecommendations.modelName,
        cachedAt: loggedRecommendations.createdAt,
        radiusKm,
        usedDefaultPreferences,
      });
    }

    const prompt = buildPrompt({ latitude, longitude, radiusKm, preferences });

    try {
      const generated = await generateWithFallback({
        supabase,
        cacheKey,
        apiKey: geminiApiKey,
        prompt,
      });

      await saveCache({
        supabase,
        cacheKey,
        latitudeBucket,
        longitudeBucket,
        radiusKm,
        preferenceHash,
        recommendations: generated.recommendations,
        modelName: generated.modelName,
      });

      await saveRecommendationLog({
        supabase,
        userId,
        latitude,
        longitude,
        preferences,
        prompt,
        recommendations: generated.recommendations,
        cacheKey,
        modelName: generated.modelName,
        latencyMs: Date.now() - startTime,
      });

      return recommendationResponse(generated.recommendations, {
        source: "gemini",
        modelName: generated.modelName,
        cachedAt: new Date().toISOString(),
        radiusKm,
        usedDefaultPreferences,
      });
    } catch (error) {
      // Stale-while-error: an expired result is still safer and more useful
      // than an empty map when Gemini is unavailable or quota-limited.
      if (cached && cachedRecommendations.length > 0) {
        const ageMs = now - Date.parse(cached.created_at);
        if (ageMs <= CACHE_STALE_DAYS * 24 * 60 * 60 * 1000) {
          return recommendationResponse(cachedRecommendations, {
            source: "stale_supabase_cache",
            modelName: cached.model_name,
            cachedAt: cached.created_at,
            radiusKm,
            usedDefaultPreferences,
          });
        }
      }

      if (error instanceof GeminiRequestError) {
        const status = error.status === 429 ? 429 : 503;
        return Response.json(
          {
            error: error.status === 429
              ? "AI recommendation quota has been reached. Please try again later."
              : "The AI recommendation service is temporarily unavailable.",
          },
          { status },
        );
      }
      throw error;
    }
  } catch (error) {
    console.error(error);
    return Response.json(
      {
        error: error instanceof Error
          ? error.message
          : "Unknown recommendation error.",
      },
      { status: 500 },
    );
  }
});

async function currentUserId(
  supabase: SupabaseAdminClient,
  authHeader: string | null,
): Promise<string | null> {
  if (!authHeader?.startsWith("Bearer ")) return null;
  const token = authHeader.slice(7).trim();
  if (!token) return null;

  const { data, error } = await supabase.auth.getUser(token);
  if (error) return null;
  return data.user?.id ?? null;
}

async function loadPreferences(
  supabase: SupabaseAdminClient,
  userId: string | null,
): Promise<{ preferences: Preferences; usedDefaultPreferences: boolean }> {
  if (!userId) {
    return { preferences: DEFAULT_PREFERENCES, usedDefaultPreferences: true };
  }

  const { data, error } = await supabase
    .from("preferences")
    .select(`
      attraction_interests,
      food_cuisine_interests,
      dietary_preferences,
      accessibility_preferences,
      category_exclusions,
      dietary_restrictions
    `)
    .eq("user_id", userId)
    .maybeSingle();
  if (error) throw error;
  if (!data) {
    return { preferences: DEFAULT_PREFERENCES, usedDefaultPreferences: true };
  }

  return {
    preferences: normalisePreferences(data),
    usedDefaultPreferences: false,
  };
}

function normalisePreferences(value: Record<string, unknown>): Preferences {
  return {
    attraction_interests: cleanArray(value.attraction_interests),
    food_cuisine_interests: cleanArray(value.food_cuisine_interests),
    dietary_preferences: cleanArray(value.dietary_preferences),
    accessibility_preferences: cleanArray(value.accessibility_preferences),
    category_exclusions: cleanArray(value.category_exclusions),
    dietary_restrictions: cleanArray(value.dietary_restrictions),
  };
}

function stablePreferences(preferences: Preferences): string {
  const canonical = Object.fromEntries(
    Object.entries(preferences).map(([key, values]) => [
      key,
      [...new Set(values.map((value: string) => value.trim().toLowerCase()))]
        .sort(),
    ]),
  );
  return JSON.stringify(canonical);
}

async function findCompatibleRecommendationLog({
  supabase,
  userId,
  latitude,
  longitude,
  preferences,
}: {
  supabase: SupabaseAdminClient;
  userId: string | null;
  latitude: number;
  longitude: number;
  preferences: Preferences;
}): Promise<
  {
    recommendations: RecommendationItem[];
    modelName: string;
    createdAt: string;
  } | null
> {
  const cutoff = new Date(
    Date.now() - CACHE_STALE_DAYS * 24 * 60 * 60 * 1000,
  ).toISOString();

  let query = supabase
    .from("recommendation_logs")
    .select(`
      response_json,
      preferences_snapshot,
      model_name,
      created_at,
      current_latitude,
      current_longtitude
    `)
    .eq("recommendation_type", "nearby")
    .eq("status", "success")
    .gte("created_at", cutoff)
    .order("created_at", { ascending: false })
    .limit(25);
  query = userId ? query.eq("user_id", userId) : query.is("user_id", null);

  const { data, error } = await query;
  if (error) {
    console.error("Recommendation-log cache lookup failed:", error);
    return null;
  }

  const expectedPreferences = stablePreferences(preferences);
  for (const row of (data ?? []) as Array<Record<string, any>>) {
    const rowLatitude = Number(row.current_latitude);
    const rowLongitude = Number(row.current_longtitude);
    if (
      !Number.isFinite(rowLatitude) ||
      !Number.isFinite(rowLongitude) ||
      bucket(rowLatitude) !== bucket(latitude) ||
      bucket(rowLongitude) !== bucket(longitude)
    ) continue;

    const snapshot = normalisePreferences(row.preferences_snapshot ?? {});
    if (stablePreferences(snapshot) !== expectedPreferences) continue;

    const recommendations = validateRecommendations(
      row.response_json?.recommendations,
    );
    if (recommendations.length === 0) continue;

    return {
      recommendations,
      modelName: String(row.model_name ?? "previous-gemini-result"),
      createdAt: String(row.created_at),
    };
  }
  return null;
}

async function saveCache({
  supabase,
  cacheKey,
  latitudeBucket,
  longitudeBucket,
  radiusKm,
  preferenceHash,
  recommendations,
  modelName,
}: {
  supabase: SupabaseAdminClient;
  cacheKey: string;
  latitudeBucket: string;
  longitudeBucket: string;
  radiusKm: number;
  preferenceHash: string;
  recommendations: RecommendationItem[];
  modelName: string;
}) {
  const now = new Date();
  const { error } = await supabase
    .from("nearby_recommendation_cache")
    .upsert({
      cache_key: cacheKey,
      latitude_bucket: Number(latitudeBucket),
      longitude_bucket: Number(longitudeBucket),
      radius_km: radiusKm,
      preference_hash: preferenceHash,
      prompt_version: PROMPT_VERSION,
      recommendations,
      model_name: modelName,
      created_at: now.toISOString(),
      expires_at: new Date(
        now.getTime() + CACHE_TTL_HOURS * 60 * 60 * 1000,
      ).toISOString(),
    });
  if (error) throw error;
}

async function generateWithFallback({
  supabase,
  cacheKey,
  apiKey,
  prompt,
}: {
  supabase: SupabaseAdminClient;
  cacheKey: string;
  apiKey: string;
  prompt: string;
}): Promise<{ recommendations: RecommendationItem[]; modelName: string }> {
  try {
    return await generateWithRetry(
      supabase,
      cacheKey,
      PRIMARY_MODEL,
      apiKey,
      prompt,
    );
  } catch (primaryError) {
    if (!FALLBACK_MODEL || FALLBACK_MODEL === PRIMARY_MODEL) throw primaryError;
    console.error("Primary Gemini model failed:", primaryError);
    return await generateWithRetry(
      supabase,
      cacheKey,
      FALLBACK_MODEL,
      apiKey,
      prompt,
    );
  }
}

async function generateWithRetry(
  supabase: SupabaseAdminClient,
  cacheKey: string,
  modelName: string,
  apiKey: string,
  prompt: string,
): Promise<{ recommendations: RecommendationItem[]; modelName: string }> {
  try {
    return await generate(supabase, cacheKey, modelName, apiKey, prompt);
  } catch (error) {
    if (!(error instanceof GeminiRequestError) || error.status !== 503) {
      throw error;
    }
    await delay(600 + Math.floor(Math.random() * 400));
    return await generate(supabase, cacheKey, modelName, apiKey, prompt);
  }
}

async function generate(
  supabase: SupabaseAdminClient,
  cacheKey: string,
  modelName: string,
  apiKey: string,
  prompt: string,
): Promise<{ recommendations: RecommendationItem[]; modelName: string }> {
  await reserveAiAttempt(supabase, cacheKey, modelName);
  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${modelName}:generateContent`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": apiKey,
      },
      body: JSON.stringify({
        contents: [{ role: "user", parts: [{ text: prompt }] }],
        generationConfig: {
          responseMimeType: "application/json",
          temperature: 0.35,
          maxOutputTokens: 1800,
        },
      }),
    },
  );

  const data = await response.json();
  if (!response.ok) {
    console.error(`Gemini ${modelName} error:`, data);
    throw new GeminiRequestError(
      Number(response.status),
      data?.error?.message ?? "Gemini recommendation request failed.",
    );
  }

  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) throw new Error("Gemini returned no recommendation.");

  const parsed = JSON.parse(removeCodeFences(String(text)));
  const recommendations = validateRecommendations(parsed?.recommendations);
  if (recommendations.length === 0) {
    throw new Error("Gemini returned no valid recommendation.");
  }
  return { recommendations, modelName };
}

async function reserveAiAttempt(
  supabase: SupabaseAdminClient,
  cacheKey: string,
  modelName: string,
) {
  const rollingWindowStart = new Date(
    Date.now() - 24 * 60 * 60 * 1000,
  ).toISOString();
  const { count, error: countError } = await supabase
    .from("nearby_recommendation_ai_usage")
    .select("id", { count: "exact", head: true })
    .gte("attempted_at", rollingWindowStart);
  if (countError) throw countError;
  if ((count ?? 0) >= DAILY_CALL_BUDGET) {
    throw new GeminiRequestError(
      429,
      "The app's AI recommendation budget has been reached.",
    );
  }

  const { error: insertError } = await supabase
    .from("nearby_recommendation_ai_usage")
    .insert({
      cache_key: cacheKey,
      model_name: modelName,
      attempted_at: new Date().toISOString(),
    });
  if (insertError) throw insertError;
}

async function saveRecommendationLog({
  supabase,
  userId,
  latitude,
  longitude,
  preferences,
  prompt,
  recommendations,
  cacheKey,
  modelName,
  latencyMs,
}: {
  supabase: SupabaseAdminClient;
  userId: string | null;
  latitude: number;
  longitude: number;
  preferences: Preferences;
  prompt: string;
  recommendations: RecommendationItem[];
  cacheKey: string;
  modelName: string;
  latencyMs: number;
}) {
  const { error } = await supabase.from("recommendation_logs").insert({
    user_id: userId,
    recommendation_type: "nearby",
    current_latitude: latitude,
    current_longtitude: longitude,
    current_attraction_id: null,
    preferences_snapshot: preferences,
    prompt,
    response_json: { recommendations },
    context_hash: cacheKey,
    status: "success",
    model_name: modelName,
    latency_ms: latencyMs,
    created_at: new Date().toISOString(),
  });
  if (error) console.error("Recommendation log error:", error);
}

function recommendationResponse(
  recommendations: RecommendationItem[],
  meta: {
    source: string;
    modelName: string;
    cachedAt: string;
    radiusKm: number;
    usedDefaultPreferences: boolean;
  },
) {
  return Response.json({
    recommendations,
    meta: {
      source: meta.source,
      model_name: meta.modelName,
      cached_at: meta.cachedAt,
      radius_km: meta.radiusKm,
      returned_count: recommendations.length,
      used_default_preferences: meta.usedDefaultPreferences,
      prompt_version: PROMPT_VERSION,
    },
  });
}

function buildPrompt({
  latitude,
  longitude,
  radiusKm,
  preferences,
}: {
  latitude: number;
  longitude: number;
  radiusKm: number;
  preferences: Preferences;
}): string {
  return `
You are NarrateMy's tourism recommendation engine for Malaysia.

Recommend 5 to 7 real, identifiable tourist places located approximately
within ${radiusKm} km of latitude ${latitude}, longitude ${longitude}.

TOURIST PREFERENCES
Attraction interests: ${JSON.stringify(preferences.attraction_interests)}
Food and cuisine interests: ${
    JSON.stringify(preferences.food_cuisine_interests)
  }
Dietary preferences: ${JSON.stringify(preferences.dietary_preferences)}
Dietary restrictions: ${JSON.stringify(preferences.dietary_restrictions)}
Accessibility preferences: ${
    JSON.stringify(preferences.accessibility_preferences)
  }
Excluded categories: ${JSON.stringify(preferences.category_exclusions)}

RULES
1. Preferences have priority and excluded categories must not be returned.
2. Dietary preferences and restrictions are hard constraints for food venues.
3. If dietary compatibility is uncertain, prefer a non-food attraction.
4. Provide variety, with at most two recommendations from one category.
5. Do not duplicate an attraction.
6. Give one short personalised reason per recommendation.
7. Return JSON only in this exact shape:
{"recommendations":[{"name":"Place name","category":"Museum","address":"Known or approximate address","rank":1,"reason":"Why it fits"}]}
`.trim();
}

function validateRecommendations(value: unknown): RecommendationItem[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item) => item && typeof item === "object")
    .map((item, index) => {
      const row = item as Record<string, unknown>;
      return {
        name: String(row.name ?? "").trim(),
        category: String(row.category ?? "").trim(),
        address: row.address == null ? null : String(row.address).trim(),
        reason: String(row.reason ?? "").trim(),
        rank: index + 1,
      };
    })
    .filter((item) => item.name && item.category && item.reason)
    .slice(0, 7);
}

function cleanArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return [
    ...new Set(
      value.map((item) => String(item).trim()).filter((item) =>
        item.length > 0
      ),
    ),
  ].sort((a, b) => a.localeCompare(b));
}

function bucket(value: number): string {
  return (Math.round(value * 100) / 100).toFixed(2);
}

function removeCodeFences(text: string): string {
  return text
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();
}

async function sha256(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`Required environment variable ${name} is missing.`);
  }
  return value;
}

function numberFromEnv(name: string, fallback: number): number {
  const value = Number(Deno.env.get(name));
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(maximum, Math.max(minimum, value));
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

class GeminiRequestError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message);
    this.name = "GeminiRequestError";
  }
}
