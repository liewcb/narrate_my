// deno-lint-ignore-file no-explicit-any
import { createClient } from "npm:@supabase/supabase-js@2";

// This project does not currently generate Supabase Database TypeScript
// definitions. Keep the admin client untyped at this boundary; every value
// read from PostgREST is explicitly normalised before it enters domain logic.
type SupabaseAdminClient = any;

const PRIMARY_MODEL = Deno.env.get("GEMINI_RECOMMENDATION_MODEL") ??
  "gemini-3.5-flash-lite";
const FALLBACK_MODEL = Deno.env.get("GEMINI_RECOMMENDATION_FALLBACK_MODEL") ??
  "gemini-3.6-flash";
const PROMPT_VERSION = "nearby-v4-accessibility-proximity";
const DEFAULT_RADIUS_KM = 10;
const MAX_RADIUS_KM = 20;
const MAX_RECOMMENDATIONS = 13;
const GEMINI_REQUEST_TIMEOUT_MS = 25_000;
const PLACES_REQUEST_TIMEOUT_MS = 10_000;
const CACHE_TTL_HOURS = numberFromEnv("RECOMMENDATION_CACHE_TTL_HOURS", 24);
const CACHE_STALE_DAYS = numberFromEnv("RECOMMENDATION_CACHE_STALE_DAYS", 7);
const DAILY_CALL_BUDGET = numberFromEnv("GEMINI_DAILY_CALL_BUDGET", 100);

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
  place_id?: string;
  latitude?: number;
  longitude?: number;
  rating?: number;
  photo_reference?: string;
  accessibility_evidence?: string;
}

interface PlaceAccessibilityOptions {
  wheelchairAccessibleParking: boolean | null;
  wheelchairAccessibleEntrance: boolean | null;
  wheelchairAccessibleRestroom: boolean | null;
  wheelchairAccessibleSeating: boolean | null;
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
    const placesApiKey = requiredEnv("GOOGLE_PLACES_API_KEY");
    const photoSigningSecret = requiredEnv("PLACES_PHOTO_SIGNING_SECRET");
    const supabase = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const body = await req.json();
    const latitude = Number(body.latitude);
    const longitude = Number(body.longitude);
    const radiusKm = clamp(
      body.radius_km == null ? DEFAULT_RADIUS_KM : Number(body.radius_km),
      1,
      MAX_RADIUS_KM,
    );
    const maximumRadiusKm = MAX_RADIUS_KM;

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
        maximumRadiusKm.toFixed(2),
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
      preferences,
    );
    const now = Date.now();
    if (
      cached &&
      cachedRecommendations.length > 0 &&
      Date.parse(cached.expires_at) > now
    ) {
      return await recommendationResponse(
        cachedRecommendations,
        {
          source: "supabase_cache",
          modelName: cached.model_name,
          cachedAt: cached.created_at,
          radiusKm,
          usedDefaultPreferences,
        },
        supabaseUrl,
        photoSigningSecret,
      );
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
      try {
        const resolvedLoggedRecommendations = await resolveRecommendations({
          recommendations: loggedRecommendations.recommendations,
          latitude,
          longitude,
          radiusKm: maximumRadiusKm,
          apiKey: placesApiKey,
          preferences,
        });
        if (resolvedLoggedRecommendations.length > 0) {
          await saveCache({
            supabase,
            cacheKey,
            latitudeBucket,
            longitudeBucket,
            radiusKm,
            preferenceHash,
            recommendations: resolvedLoggedRecommendations,
            modelName: loggedRecommendations.modelName,
          });
          return await recommendationResponse(
            resolvedLoggedRecommendations,
            {
              source: "recommendation_log_cache",
              modelName: loggedRecommendations.modelName,
              cachedAt: loggedRecommendations.createdAt,
              radiusKm,
              usedDefaultPreferences,
            },
            supabaseUrl,
            photoSigningSecret,
          );
        }
      } catch (error) {
        // An old recommendation log may contain a place Google can no longer
        // resolve. Continue to Gemini instead of failing the whole request.
        console.error("Recommendation-log Places enrichment failed:", error);
      }
    }

    const prompt = buildPrompt({
      latitude,
      longitude,
      radiusKm,
      maximumRadiusKm,
      preferences,
    });

    try {
      const generated = await generateWithFallback({
        supabase,
        cacheKey,
        apiKey: geminiApiKey,
        prompt,
      });
      const resolvedRecommendations = await resolveRecommendations({
        recommendations: generated.recommendations,
        latitude,
        longitude,
        radiusKm: maximumRadiusKm,
        apiKey: placesApiKey,
        preferences,
      });

      await saveCache({
        supabase,
        cacheKey,
        latitudeBucket,
        longitudeBucket,
        radiusKm,
        preferenceHash,
        recommendations: resolvedRecommendations,
        modelName: generated.modelName,
      });

      await saveRecommendationLog({
        supabase,
        userId,
        latitude,
        longitude,
        preferences,
        prompt,
        recommendations: resolvedRecommendations,
        cacheKey,
        modelName: generated.modelName,
        latencyMs: Date.now() - startTime,
      });

      return await recommendationResponse(
        resolvedRecommendations,
        {
          source: "gemini",
          modelName: generated.modelName,
          cachedAt: new Date().toISOString(),
          radiusKm,
          usedDefaultPreferences,
        },
        supabaseUrl,
        photoSigningSecret,
      );
    } catch (error) {
      // Stale-while-error: an expired result is still safer and more useful
      // than an empty map when Gemini is unavailable or quota-limited.
      if (cached && cachedRecommendations.length > 0) {
        const ageMs = now - Date.parse(cached.created_at);
        if (ageMs <= CACHE_STALE_DAYS * 24 * 60 * 60 * 1000) {
          return await recommendationResponse(
            cachedRecommendations,
            {
              source: "stale_supabase_cache",
              modelName: cached.model_name,
              cachedAt: cached.created_at,
              radiusKm,
              usedDefaultPreferences,
            },
            supabaseUrl,
            photoSigningSecret,
          );
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
      if (error instanceof PlacesRequestError) {
        return Response.json(
          { error: "Nearby place details are temporarily unavailable." },
          { status: 503 },
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
      prompt,
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
    if (
      !String(row.prompt ?? "").includes(`POLICY VERSION: ${PROMPT_VERSION}`)
    ) {
      continue;
    }
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
      preferences,
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

async function resolveRecommendations({
  recommendations,
  latitude,
  longitude,
  radiusKm,
  apiKey,
  preferences,
}: {
  recommendations: RecommendationItem[];
  latitude: number;
  longitude: number;
  radiusKm: number;
  apiKey: string;
  preferences: Preferences;
}): Promise<RecommendationItem[]> {
  const errors: unknown[] = [];
  const resolved: Array<RecommendationItem | null> = await Promise.all(
    recommendations.map(async (recommendation) => {
      try {
        const place = await searchPlace({
          recommendation,
          latitude,
          longitude,
          radiusKm,
          apiKey,
        });
        if (!place) return null;
        const distanceKm = haversineKm(
          latitude,
          longitude,
          place.location.latitude,
          place.location.longitude,
        );
        if (distanceKm > radiusKm) return null;
        if (!isAccessiblePlace(recommendation, place, preferences)) return null;
        return {
          ...recommendation,
          place_id: place.id,
          address: place.formattedAddress ?? recommendation.address,
          latitude: place.location.latitude,
          longitude: place.location.longitude,
          ...(place.rating == null ? {} : { rating: place.rating }),
          ...(place.photoReference == null
            ? {}
            : { photo_reference: place.photoReference }),
        } satisfies RecommendationItem;
      } catch (error) {
        errors.push(error);
        console.error(
          `Unable to resolve Google Place for ${recommendation.name}:`,
          error,
        );
        return null;
      }
    }),
  );

  const usable = resolved
    .filter((item): item is RecommendationItem => item != null)
    .sort((a, b) => {
      const aDistance = haversineKm(
        latitude,
        longitude,
        a.latitude!,
        a.longitude!,
      );
      const bDistance = haversineKm(
        latitude,
        longitude,
        b.latitude!,
        b.longitude!,
      );
      const aBand = aDistance <= 3 ? 0 : aDistance <= DEFAULT_RADIUS_KM ? 1 : 2;
      const bBand = bDistance <= 3 ? 0 : bDistance <= DEFAULT_RADIUS_KM ? 1 : 2;
      return aBand - bBand || a.rank - b.rank || aDistance - bDistance;
    })
    .map((item, index) => ({ ...item, rank: index + 1 }));
  if (usable.length === 0) {
    const firstError = errors[0];
    if (firstError instanceof PlacesRequestError) throw firstError;
    if (accessibilityProfile(preferences).hasConstraints) return [];
    throw new PlacesRequestError(
      503,
      "Google Places could not verify any recommended locations.",
    );
  }
  return usable;
}

async function searchPlace({
  recommendation,
  latitude,
  longitude,
  radiusKm,
  apiKey,
}: {
  recommendation: RecommendationItem;
  latitude: number;
  longitude: number;
  radiusKm: number;
  apiKey: string;
}): Promise<
  {
    id: string;
    formattedAddress: string | null;
    location: { latitude: number; longitude: number };
    rating: number | null;
    photoReference: string | null;
    accessibilityOptions: PlaceAccessibilityOptions;
  } | null
> {
  const query = [recommendation.name, recommendation.address]
    .filter((value) => value && String(value).trim())
    .join(", ");
  const response = await fetch(
    "https://places.googleapis.com/v1/places:searchText",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask": [
          "places.id",
          "places.displayName",
          "places.formattedAddress",
          "places.location",
          "places.rating",
          "places.photos",
          "places.accessibilityOptions",
        ].join(","),
      },
      body: JSON.stringify({
        textQuery: query,
        maxResultCount: 5,
        locationBias: {
          circle: {
            center: { latitude, longitude },
            radius: clamp(radiusKm * 1000, 1, 50000),
          },
        },
      }),
      signal: AbortSignal.timeout(PLACES_REQUEST_TIMEOUT_MS),
    },
  );
  const data = await response.json();
  if (!response.ok) {
    throw new PlacesRequestError(
      response.status,
      data?.error?.message ?? "Google Places Text Search failed.",
    );
  }

  const places = Array.isArray(data?.places) ? data.places : [];
  if (places.length === 0) return null;
  const targetName = normaliseName(recommendation.name);
  const matched = places.find((place: Record<string, unknown>) => {
    const displayName = (place.displayName as Record<string, unknown> | null)
      ?.text;
    const candidateName = normaliseName(String(displayName ?? ""));
    return candidateName === targetName || candidateName.includes(targetName) ||
      targetName.includes(candidateName);
  }) ?? places[0];
  const location = matched.location as Record<string, unknown> | undefined;
  const resolvedLatitude = Number(location?.latitude);
  const resolvedLongitude = Number(location?.longitude);
  if (
    !Number.isFinite(resolvedLatitude) ||
    !Number.isFinite(resolvedLongitude)
  ) {
    return null;
  }
  const photos = Array.isArray(matched.photos) ? matched.photos : [];
  const photoReference = photos[0]?.name == null
    ? null
    : String(photos[0].name).trim() || null;
  const rating = Number(matched.rating);
  const accessibilityOptions = parseAccessibilityOptions(
    matched.accessibilityOptions,
  );

  return {
    id: String(matched.id ?? "").trim(),
    formattedAddress: matched.formattedAddress == null
      ? null
      : String(matched.formattedAddress).trim() || null,
    location: {
      latitude: resolvedLatitude,
      longitude: resolvedLongitude,
    },
    rating: Number.isFinite(rating) ? rating : null,
    photoReference,
    accessibilityOptions,
  };
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
          maxOutputTokens: 3200,
        },
      }),
      signal: AbortSignal.timeout(GEMINI_REQUEST_TIMEOUT_MS),
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

async function recommendationResponse(
  recommendations: RecommendationItem[],
  meta: {
    source: string;
    modelName: string;
    cachedAt: string;
    radiusKm: number;
    usedDefaultPreferences: boolean;
  },
  supabaseUrl: string,
  photoSigningSecret: string,
): Promise<Response> {
  const recommendationsWithPhotos = await Promise.all(
    recommendations.map(async (recommendation) => ({
      ...recommendation,
      ...(recommendation.photo_reference == null ? {} : {
        image_url: await buildSignedPhotoUrl(
          supabaseUrl,
          recommendation.photo_reference,
          photoSigningSecret,
        ),
      }),
    })),
  );
  return Response.json({
    recommendations: recommendationsWithPhotos,
    meta: {
      source: meta.source,
      model_name: meta.modelName,
      cached_at: meta.cachedAt,
      radius_km: meta.radiusKm,
      maximum_radius_km: MAX_RADIUS_KM,
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
  maximumRadiusKm,
  preferences,
}: {
  latitude: number;
  longitude: number;
  radiusKm: number;
  maximumRadiusKm: number;
  preferences: Preferences;
}): string {
  const accessibilityRules = buildAccessibilityRules(preferences);
  return `
You are NarrateMy's tourism recommendation engine for Malaysia.

POLICY VERSION: ${PROMPT_VERSION}

Recommend 10 to ${MAX_RECOMMENDATIONS} real, identifiable tourist places. Return at least 7
when 7 suitable places exist. Never invent a place merely to reach the target.

GEOGRAPHIC SEARCH POLICY
- Search closest-first from latitude ${latitude}, longitude ${longitude}.
- First fill the list with suitable places within 0-3 km so dense areas such
  as Bukit Bintang/Pavilion are represented before farther districts.
- Then use suitable places from 3-${radiusKm} km.
- Only when fewer than 7 suitable places exist within ${radiusKm} km may you
  expand to the outer ring from ${radiusKm}-${maximumRadiusKm} km.
- Never recommend anything farther than ${maximumRadiusKm} km.
- Rank inner-area places before outer-ring places; distance is a primary
  ranking factor after all hard constraints are satisfied.

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

HARD ACCESSIBILITY CONSTRAINTS
${accessibilityRules}

RULES
1. Accessibility rules and excluded categories are hard constraints. Never
   relax them to reach the requested number of recommendations.
2. Dietary preferences and restrictions are hard constraints for food venues.
3. If dietary compatibility is uncertain, prefer a non-food attraction.
4. Provide variety, with at most two recommendations from one category.
5. Do not duplicate an attraction.
6. Give one short personalised reason per recommendation.
7. When accessibility constraints are active, state the specific known feature
   that satisfies them in accessibility_evidence. If compatibility is unknown,
   omit the place. Use an empty string only when no accessibility constraint is active.
8. Return JSON only in this exact shape:
{"recommendations":[{"name":"Place name","category":"Museum","address":"Known or approximate address","rank":1,"reason":"Why it fits","accessibility_evidence":"Step-free entrance and lifts"}]}
`.trim();
}

function validateRecommendations(
  value: unknown,
  preferences: Preferences = DEFAULT_PREFERENCES,
): RecommendationItem[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item) => item && typeof item === "object")
    .map((item, index) => {
      const row = item as Record<string, unknown>;
      const latitude = optionalNumber(row.latitude);
      const longitude = optionalNumber(row.longitude);
      const rating = optionalNumber(row.rating);
      const rank = optionalNumber(row.rank);
      return {
        name: String(row.name ?? "").trim(),
        category: String(row.category ?? "").trim(),
        address: row.address == null ? null : String(row.address).trim(),
        reason: String(row.reason ?? "").trim(),
        rank: rank == null ? index + 1 : Math.max(1, Math.trunc(rank)),
        ...(optionalString(row.place_id) == null
          ? {}
          : { place_id: optionalString(row.place_id)! }),
        ...(latitude == null ? {} : { latitude }),
        ...(longitude == null ? {} : { longitude }),
        ...(rating == null ? {} : { rating }),
        ...(optionalString(row.photo_reference) == null
          ? {}
          : { photo_reference: optionalString(row.photo_reference)! }),
        ...(optionalString(row.accessibility_evidence) == null ? {} : {
          accessibility_evidence: optionalString(
            row.accessibility_evidence,
          )!,
        }),
      };
    })
    .filter((item) => item.name && item.category && item.reason)
    .filter((item) =>
      generatedAccessibilityEvidenceIsCompatible(item, preferences)
    )
    .slice(0, MAX_RECOMMENDATIONS);
}

function buildAccessibilityRules(preferences: Preferences): string {
  const profile = accessibilityProfile(preferences);
  if (!profile.hasConstraints) {
    return "No accessibility constraint is active.";
  }

  const rules: string[] = [];
  if (profile.wheelchair) {
    rules.push(
      "- WHEELCHAIR ACCESSIBLE: return only places with a known step-free, " +
        "wheelchair-accessible entrance and usable lifts/ramps where needed. " +
        "Reject hiking, trekking, climbing, stairs-only, steep, cave, and " +
        "rough- or uneven-terrain experiences.",
    );
  }
  if (profile.mobility) {
    rules.push(
      "- MOBILITY ASSISTANCE: return only low-exertion places with a known " +
        "accessible entrance, short/easy routes, and seating or rest options. " +
        "Reject hikes, trails, long walking tours, steep slopes, climbing, " +
        "stairs-only access, and prolonged-standing activities.",
    );
  }
  if (profile.visual) {
    rules.push(
      "- VISUAL ASSISTANCE: return only places with a known audio guide, " +
        "audio description, tactile/Braille material, guided assistance, or " +
        "another concrete non-visual way to experience the attraction.",
    );
  }
  rules.push(
    "- If the required accessibility support cannot be stated confidently, " +
      "do not recommend that place. Returning fewer results is correct.",
  );
  return rules.join("\n");
}

function generatedAccessibilityEvidenceIsCompatible(
  recommendation: RecommendationItem,
  preferences: Preferences,
): boolean {
  const profile = accessibilityProfile(preferences);
  if (!profile.hasConstraints) return true;

  const evidence = recommendation.accessibility_evidence?.trim() ?? "";
  if (!evidence) return false;

  if (
    (profile.wheelchair || profile.mobility) &&
    !/(wheelchair|step[- ]?free|ramp|lift|elevator|accessible entrance|accessible parking|mobility|seating|rest area)/i
      .test(evidence)
  ) {
    return false;
  }
  if (
    profile.visual &&
    !/(audio guide|audio description|tactile|braille|guided (tour|assistance)|staff assistance|non-visual)/i
      .test(evidence)
  ) {
    return false;
  }
  return true;
}

function isAccessiblePlace(
  recommendation: RecommendationItem,
  place: { accessibilityOptions: PlaceAccessibilityOptions },
  preferences: Preferences,
): boolean {
  const profile = accessibilityProfile(preferences);
  if (!profile.hasConstraints) return true;
  if (
    !generatedAccessibilityEvidenceIsCompatible(recommendation, preferences)
  ) {
    return false;
  }

  if (
    (profile.wheelchair || profile.mobility) &&
    place.accessibilityOptions.wheelchairAccessibleEntrance !== true
  ) {
    return false;
  }

  if (
    (profile.wheelchair || profile.mobility) &&
    isMobilityRiskText(
      `${recommendation.name} ${recommendation.category} ${recommendation.reason}`,
    )
  ) {
    return false;
  }
  return true;
}

function accessibilityProfile(preferences: Preferences) {
  const selected = preferences.accessibility_preferences.map((value) =>
    value.trim().toLowerCase()
  );
  const wheelchair = selected.some((value) => value.includes("wheelchair"));
  const mobility = selected.some((value) => value.includes("mobility"));
  const visual = selected.some((value) => value.includes("visual"));
  return {
    wheelchair,
    mobility,
    visual,
    hasConstraints: wheelchair || mobility || visual,
  };
}

function isMobilityRiskText(value: string): boolean {
  return /\b(hike|hiking|trek|trekking|trail|mountain|mountaineering|climb|climbing|stairs-only|steep slope|rough terrain|uneven terrain|long walking tour)\b/i
    .test(value);
}

function parseAccessibilityOptions(value: unknown): PlaceAccessibilityOptions {
  const options = value && typeof value === "object"
    ? value as Record<string, unknown>
    : {};
  return {
    wheelchairAccessibleParking: optionalBoolean(
      options.wheelchairAccessibleParking,
    ),
    wheelchairAccessibleEntrance: optionalBoolean(
      options.wheelchairAccessibleEntrance,
    ),
    wheelchairAccessibleRestroom: optionalBoolean(
      options.wheelchairAccessibleRestroom,
    ),
    wheelchairAccessibleSeating: optionalBoolean(
      options.wheelchairAccessibleSeating,
    ),
  };
}

function haversineKm(
  latitude1: number,
  longitude1: number,
  latitude2: number,
  longitude2: number,
): number {
  const toRadians = (value: number) => value * Math.PI / 180;
  const latitudeDelta = toRadians(latitude2 - latitude1);
  const longitudeDelta = toRadians(longitude2 - longitude1);
  const a = Math.sin(latitudeDelta / 2) ** 2 +
    Math.cos(toRadians(latitude1)) * Math.cos(toRadians(latitude2)) *
      Math.sin(longitudeDelta / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

async function buildSignedPhotoUrl(
  supabaseUrl: string,
  photoReference: string,
  signingSecret: string,
): Promise<string> {
  // The phone cache is fresh for 24 hours. Keep its image links usable for
  // that full period, with a small allowance for clock skew and network time.
  const expires = Math.floor(Date.now() / 1000) + 25 * 60 * 60;
  const signature = await hmacSha256(
    `${photoReference}|${expires}`,
    signingSecret,
  );
  const url = new URL(`${supabaseUrl}/functions/v1/place-photo`);
  url.searchParams.set("resource", photoReference);
  url.searchParams.set("expires", String(expires));
  url.searchParams.set("signature", signature);
  return url.toString();
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

function optionalString(value: unknown): string | null {
  const text = value == null ? "" : String(value).trim();
  return text || null;
}

function optionalNumber(value: unknown): number | null {
  if (value == null || value === "") return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function optionalBoolean(value: unknown): boolean | null {
  return typeof value === "boolean" ? value : null;
}

function normaliseName(value: string): string {
  return value.toLowerCase().replaceAll(/[^a-z0-9]/g, "");
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
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
    this.name = "GeminiRequestError";
  }
}

class PlacesRequestError extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
    this.name = "PlacesRequestError";
  }
}
