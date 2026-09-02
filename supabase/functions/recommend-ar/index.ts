import { createClient } from "npm:@supabase/supabase-js@2";

type SupabaseAdminClient = any;

const PRIMARY_MODEL = Deno.env.get("GEMINI_RECOMMENDATION_MODEL") ??
  "gemini-3.5-flash-lite";
const FALLBACK_MODEL = Deno.env.get("GEMINI_RECOMMENDATION_FALLBACK_MODEL") ??
  "gemini-3.6-flash";
const PROMPT_VERSION = "ar-context-v1";
const DEFAULT_RADIUS_KM = 30;
const CACHE_TTL_HOURS = 24;
const DAILY_CALL_BUDGET = numberFromEnv("GEMINI_DAILY_CALL_BUDGET", 15);

interface Preferences {
  attraction_interests: string[];
  food_cuisine_interests: string[];
  dietary_preferences: string[];
  accessibility_preferences: string[];
  category_exclusions: string[];
  dietary_restrictions: string[];
}

interface ARSite {
  siteId: string;
  displayName: string;
  latitude: number;
  longitude: number;
  address: string | null;
  category: string | null;
  googlePlaceIds: string[];
}

interface Candidate {
  attractionId: string;
  markerId: string;
  siteId: string | null;
  name: string;
  summary: string;
  labels: string[];
  category: string;
  latitude: number;
  longitude: number;
  distanceKm: number;
  updatedAt: string;
  address: string | null;
  googlePlaceId: string | null;
}

interface RankedCandidate extends Candidate {
  reason: string;
  relationship: string;
  rank: number;
}

interface RecommendationItem extends RankedCandidate {
  placeId: string;
  resolvedName: string;
  resolvedAddress: string;
  resolvedLatitude: number;
  resolvedLongitude: number;
  rating: number | null;
  photoReference: string | null;
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
  const startedAt = Date.now();
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
    const currentMarkerId = optionalString(body.current_marker_id);
    const currentAttractionName = optionalString(body.current_attraction_name);
    const latitude = Number(body.latitude);
    const longitude = Number(body.longitude);
    const radiusKm = clamp(
      body.radius_km == null ? DEFAULT_RADIUS_KM : Number(body.radius_km),
      2,
      50,
    );
    const excludedMarkerIds = new Set([
      ...cleanArray(body.excluded_marker_ids),
      ...(currentMarkerId == null ? [] : [currentMarkerId]),
    ]);

    if (!currentMarkerId) {
      return Response.json(
        { error: "The current AR marker is required." },
        { status: 400 },
      );
    }
    if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90) {
      return Response.json({ error: "Invalid latitude." }, { status: 400 });
    }
    if (!Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
      return Response.json({ error: "Invalid longitude." }, { status: 400 });
    }

    const userId = await currentUserId(
      supabase,
      req.headers.get("Authorization"),
    );
    const { preferences, usedDefaultPreferences } = await loadPreferences(
      supabase,
      userId,
    );

    const attractionRows = await loadAttractions(supabase);
    const current = attractionRows.find((item) =>
      item.markerId === currentMarkerId && currentAttractionName != null &&
      normaliseName(item.name) === normaliseName(currentAttractionName)
    ) ?? attractionRows.find((item) => item.markerId === currentMarkerId);
    if (!current) {
      return Response.json(
        { error: "The selected AR attraction could not be found." },
        { status: 404 },
      );
    }

    const siteIds = cleanArray(
      attractionRows.map((item) => item.siteId).filter(Boolean),
    );
    const sites = await loadSites(supabase, siteIds);
    const candidates = buildCandidates({
      attractionRows,
      sites,
      current,
      latitude,
      longitude,
      radiusKm,
      excludedMarkerIds,
      preferences,
    });

    if (candidates.length === 0) {
      return Response.json({
        recommendations: [],
        meta: {
          source: "candidate_filter",
          returned_count: 0,
          used_default_preferences: usedDefaultPreferences,
          prompt_version: PROMPT_VERSION,
        },
      });
    }

    const preferenceHash = await sha256(stablePreferences(preferences));
    const candidateHash = await sha256(
      candidates.map((item) =>
        `${item.attractionId}:${item.updatedAt}:${item.distanceKm.toFixed(2)}`
      ).sort().join("|"),
    );
    const cacheKey = await sha256([
      PROMPT_VERSION,
      current.attractionId,
      current.siteId ?? "no-site",
      bucket(latitude),
      bucket(longitude),
      [...excludedMarkerIds].sort().join(","),
      preferenceHash,
      candidateHash,
    ].join("|"));

    const cached = await findCachedRecommendations(supabase, cacheKey);
    if (cached) {
      return await recommendationResponse(
        cached.recommendations,
        {
          source: "recommendation_log_cache",
          modelName: cached.modelName,
          usedDefaultPreferences,
        },
        supabaseUrl,
        photoSigningSecret,
      );
    }

    const prompt = buildPrompt({
      current,
      currentSite: current.siteId == null ? null : sites.get(current.siteId),
      latitude,
      longitude,
      preferences,
      candidates,
    });

    let ranked: RankedCandidate[];
    let modelName: string;
    let source = "gemini";
    try {
      const generated = await generateWithFallback({
        supabase,
        cacheKey,
        apiKey: geminiApiKey,
        prompt,
        candidates,
      });
      ranked = generated.recommendations;
      modelName = generated.modelName;
    } catch (error) {
      // A useful deterministic result is safer for a live AR visit than an
      // empty panel when the free Gemini quota or service is unavailable.
      console.error("Gemini AR ranking failed; using candidate fallback:", error);
      ranked = deterministicFallback(candidates, preferences);
      modelName = "deterministic-fallback";
      source = "deterministic_fallback";
    }

    const recommendations = await resolveRecommendations({
      ranked,
      sites,
      latitude,
      longitude,
      radiusKm,
      apiKey: placesApiKey,
    });
    if (recommendations.length === 0) {
      return Response.json(
        { error: "No recommended attractions could be verified on the map." },
        { status: 503 },
      );
    }

    await saveRecommendationLog({
      supabase,
      userId,
      latitude,
      longitude,
      currentAttractionId: current.attractionId,
      preferences,
      prompt,
      recommendations,
      cacheKey,
      modelName,
      latencyMs: Date.now() - startedAt,
    });

    return await recommendationResponse(
      recommendations,
      { source, modelName, usedDefaultPreferences },
      supabaseUrl,
      photoSigningSecret,
    );
  } catch (error) {
    console.error(error);
    return Response.json(
      {
        error: error instanceof Error
          ? error.message
          : "Unable to create AR recommendations.",
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
  return { preferences: normalisePreferences(data), usedDefaultPreferences: false };
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

async function loadAttractions(supabase: SupabaseAdminClient): Promise<Candidate[]> {
  const { data, error } = await supabase
    .from("Attraction")
    .select(`
      attraction_id,
      marker_id,
      site_id,
      name,
      attraction_content,
      labels,
      updated_at,
      Marker!inner(marker_id, latitude, longitude)
    `);
  if (error) throw error;

  return ((data ?? []) as Array<Record<string, unknown>>).map((row) => {
    const markerValue = row.Marker;
    const marker = Array.isArray(markerValue)
      ? markerValue[0] as Record<string, unknown> | undefined
      : markerValue as Record<string, unknown> | undefined;
    const labels = cleanArray(row.labels);
    return {
      attractionId: optionalString(row.attraction_id) ?? "",
      markerId: optionalString(row.marker_id ?? marker?.marker_id) ?? "",
      siteId: optionalString(row.site_id),
      name: optionalString(row.name) ?? "AR attraction",
      summary: truncate(optionalString(row.attraction_content) ??
        "Discover this NarrateMy AR attraction.", 420),
      labels,
      category: labels[0] ?? "AR attraction",
      latitude: Number(marker?.latitude),
      longitude: Number(marker?.longitude),
      distanceKm: 0,
      updatedAt: optionalString(row.updated_at) ?? "",
      address: null,
      googlePlaceId: null,
    };
  }).filter((item) =>
    item.attractionId && item.markerId && Number.isFinite(item.latitude) &&
    Number.isFinite(item.longitude)
  );
}

async function loadSites(
  supabase: SupabaseAdminClient,
  siteIds: string[],
): Promise<Map<string, ARSite>> {
  if (siteIds.length === 0) return new Map();
  const { data, error } = await supabase
    .from("ar_sites")
    .select(`
      site_id,
      display_name,
      latitude,
      longitude,
      address,
      category,
      google_place_ids
    `)
    .in("site_id", siteIds)
    .eq("is_active", true);
  if (error) throw error;

  const result = new Map<string, ARSite>();
  for (const row of (data ?? []) as Array<Record<string, unknown>>) {
    const site: ARSite = {
      siteId: optionalString(row.site_id) ?? "",
      displayName: optionalString(row.display_name) ?? "AR site",
      latitude: Number(row.latitude),
      longitude: Number(row.longitude),
      address: optionalString(row.address),
      category: optionalString(row.category),
      googlePlaceIds: cleanArray(row.google_place_ids),
    };
    if (site.siteId) result.set(site.siteId, site);
  }
  return result;
}

function buildCandidates({
  attractionRows,
  sites,
  current,
  latitude,
  longitude,
  radiusKm,
  excludedMarkerIds,
  preferences,
}: {
  attractionRows: Candidate[];
  sites: Map<string, ARSite>;
  current: Candidate;
  latitude: number;
  longitude: number;
  radiusKm: number;
  excludedMarkerIds: Set<string>;
  preferences: Preferences;
}): Candidate[] {
  const excludedCategories = new Set(
    preferences.category_exclusions.map((value) => value.toLowerCase()),
  );
  const grouped = new Map<string, Candidate>();

  for (const row of attractionRows) {
    if (row.attractionId === current.attractionId) continue;
    if (excludedMarkerIds.has(row.markerId)) continue;
    if (current.siteId && row.siteId === current.siteId) continue;
    if (row.name.trim().toLowerCase() === current.name.trim().toLowerCase()) continue;

    const site = row.siteId == null ? null : sites.get(row.siteId);
    const candidateLatitude = site?.latitude ?? row.latitude;
    const candidateLongitude = site?.longitude ?? row.longitude;
    const distanceKm = haversineKm(
      latitude,
      longitude,
      candidateLatitude,
      candidateLongitude,
    );
    if (distanceKm > radiusKm) continue;

    const category = site?.category ?? row.category;
    const categoryValues = [category, ...row.labels]
      .map((value) => value.toLowerCase());
    if (categoryValues.some((value) => excludedCategories.has(value))) continue;

    const item: Candidate = {
      ...row,
      name: site?.displayName ?? row.name,
      category,
      latitude: candidateLatitude,
      longitude: candidateLongitude,
      distanceKm,
      address: site?.address ?? null,
      googlePlaceId: site?.googlePlaceIds[0] ?? null,
    };
    const groupingKey = row.siteId ?? row.attractionId;
    const existing = grouped.get(groupingKey);
    if (!existing || item.distanceKm < existing.distanceKm) {
      grouped.set(groupingKey, item);
    }
  }

  return [...grouped.values()]
    .sort((a, b) => a.distanceKm - b.distanceKm)
    .slice(0, 40);
}

async function findCachedRecommendations(
  supabase: SupabaseAdminClient,
  cacheKey: string,
): Promise<{ recommendations: RecommendationItem[]; modelName: string } | null> {
  const cutoff = new Date(
    Date.now() - CACHE_TTL_HOURS * 60 * 60 * 1000,
  ).toISOString();
  const { data, error } = await supabase
    .from("recommendation_logs")
    .select("response_json, model_name")
    .eq("recommendation_type", "ar")
    .eq("context_hash", cacheKey)
    .eq("status", "success")
    .gte("created_at", cutoff)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) {
    console.error("AR recommendation cache lookup failed:", error);
    return null;
  }
  const recommendations = validateStoredRecommendations(
    data?.response_json?.recommendations,
  );
  if (recommendations.length === 0) return null;
  return {
    recommendations,
    modelName: optionalString(data?.model_name) ?? "previous-ar-result",
  };
}

function buildPrompt({
  current,
  currentSite,
  latitude,
  longitude,
  preferences,
  candidates,
}: {
  current: Candidate;
  currentSite: ARSite | null | undefined;
  latitude: number;
  longitude: number;
  preferences: Preferences;
  candidates: Candidate[];
}): string {
  const candidateList = candidates.map((item) => ({
    id: item.attractionId,
    name: item.name,
    category: item.category,
    summary: item.summary,
    labels: item.labels,
    distance_km: Number(item.distanceKm.toFixed(2)),
  }));

  return `
You are NarrateMy's AR recommendation engine for tourists in Malaysia.

The tourist is currently viewing an attraction using AR. Select exactly 3
attractions from CANDIDATE ATTRACTIONS that continue or complement the current
experience.

PRIORITY
1. Continue the story.
2. Deepen the experience.
3. Recommend nearby complementary attractions.
4. Avoid repetition.
5. Respect user preferences.
6. Treat dietary and religiously motivated food restrictions as hard rules.

NEVER RECOMMEND
- the current attraction or current site
- anything not present in CANDIDATE ATTRACTIONS
- duplicate attractions
- excluded or unsuitable attractions

CURRENT ATTRACTION
Name: ${current.name}
Site: ${currentSite?.displayName ?? current.name}
Category: ${current.category}
Description: ${current.summary}

USER CONTEXT
Attraction interests: ${JSON.stringify(preferences.attraction_interests)}
Food/cuisine interests: ${JSON.stringify(preferences.food_cuisine_interests)}
Dietary preferences: ${JSON.stringify(preferences.dietary_preferences)}
Dietary/religious restrictions: ${JSON.stringify(preferences.dietary_restrictions)}
Accessibility preferences: ${JSON.stringify(preferences.accessibility_preferences)}
Excluded categories: ${JSON.stringify(preferences.category_exclusions)}
Current location: ${latitude}, ${longitude}

CANDIDATE ATTRACTIONS
${JSON.stringify(candidateList)}

Return JSON only in this exact shape:
{"recommendations":[{"id":"candidate id","reason":"one concise personalised reason","relationship":"Continue History"}]}
`.trim();
}

async function generateWithFallback({
  supabase,
  cacheKey,
  apiKey,
  prompt,
  candidates,
}: {
  supabase: SupabaseAdminClient;
  cacheKey: string;
  apiKey: string;
  prompt: string;
  candidates: Candidate[];
}): Promise<{ recommendations: RankedCandidate[]; modelName: string }> {
  try {
    return await generateWithRetry(
      supabase,
      cacheKey,
      PRIMARY_MODEL,
      apiKey,
      prompt,
      candidates,
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
      candidates,
    );
  }
}

async function generateWithRetry(
  supabase: SupabaseAdminClient,
  cacheKey: string,
  modelName: string,
  apiKey: string,
  prompt: string,
  candidates: Candidate[],
): Promise<{ recommendations: RankedCandidate[]; modelName: string }> {
  try {
    return await generate(
      supabase,
      cacheKey,
      modelName,
      apiKey,
      prompt,
      candidates,
    );
  } catch (error) {
    if (!(error instanceof GeminiRequestError) || error.status !== 503) {
      throw error;
    }
    await delay(700);
    return await generate(
      supabase,
      cacheKey,
      modelName,
      apiKey,
      prompt,
      candidates,
    );
  }
}

async function generate(
  supabase: SupabaseAdminClient,
  cacheKey: string,
  modelName: string,
  apiKey: string,
  prompt: string,
  candidates: Candidate[],
): Promise<{ recommendations: RankedCandidate[]; modelName: string }> {
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
          temperature: 0.25,
          maxOutputTokens: 1000,
        },
      }),
    },
  );
  const data = await response.json();
  if (!response.ok) {
    throw new GeminiRequestError(
      response.status,
      data?.error?.message ?? "Gemini AR recommendation request failed.",
    );
  }
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text) throw new Error("Gemini returned no AR recommendation.");
  const parsed = JSON.parse(removeCodeFences(String(text)));
  const ranked = validateGeneratedRecommendations(
    parsed?.recommendations,
    candidates,
  );
  if (ranked.length === 0) {
    throw new Error("Gemini returned no valid candidate IDs.");
  }
  return { recommendations: ranked, modelName };
}

function validateGeneratedRecommendations(
  value: unknown,
  candidates: Candidate[],
): RankedCandidate[] {
  if (!Array.isArray(value)) return [];
  const candidateById = new Map(
    candidates.map((item) => [item.attractionId, item]),
  );
  const used = new Set<string>();
  const result: RankedCandidate[] = [];
  for (const raw of value) {
    if (!raw || typeof raw !== "object") continue;
    const row = raw as Record<string, unknown>;
    const id = optionalString(row.id ?? row.attraction_id);
    const candidate = id == null ? null : candidateById.get(id);
    if (!candidate || used.has(candidate.attractionId)) continue;
    used.add(candidate.attractionId);
    result.push({
      ...candidate,
      reason: optionalString(row.reason) ??
        "This attraction complements your current AR experience.",
      relationship: optionalString(row.relationship) ??
        "Complementary experience",
      rank: result.length + 1,
    });
    if (result.length === 3) break;
  }
  return result;
}

function deterministicFallback(
  candidates: Candidate[],
  preferences: Preferences,
): RankedCandidate[] {
  const interests = preferences.attraction_interests.map((item) =>
    item.toLowerCase()
  );
  return [...candidates]
    .sort((a, b) => {
      const aMatch = [...a.labels, a.category].some((value) =>
        interests.includes(value.toLowerCase())
      ) ? 1 : 0;
      const bMatch = [...b.labels, b.category].some((value) =>
        interests.includes(value.toLowerCase())
      ) ? 1 : 0;
      return bMatch - aMatch || a.distanceKm - b.distanceKm;
    })
    .slice(0, 3)
    .map((item, index) => ({
      ...item,
      reason: interests.length > 0
        ? "A nearby AR attraction that fits your interests and continues your visit."
        : "A nearby AR attraction that offers a complementary next experience.",
      relationship: "Nearby complement",
      rank: index + 1,
    }));
}

async function resolveRecommendations({
  ranked,
  sites,
  latitude,
  longitude,
  radiusKm,
  apiKey,
}: {
  ranked: RankedCandidate[];
  sites: Map<string, ARSite>;
  latitude: number;
  longitude: number;
  radiusKm: number;
  apiKey: string;
}): Promise<RecommendationItem[]> {
  const resolved = await Promise.all(ranked.map(async (item) => {
    try {
      const site = item.siteId == null ? null : sites.get(item.siteId);
      const place = item.googlePlaceId
        ? await getPlaceById(item.googlePlaceId, apiKey)
        : await searchPlace(
          site?.displayName ?? item.name,
          item.address,
          item.latitude,
          item.longitude,
          radiusKm,
          apiKey,
        );
      if (!place) return null;
      return {
        ...item,
        placeId: place.id,
        resolvedName: item.name,
        resolvedAddress: place.formattedAddress ?? item.address ??
          "Address unavailable",
        resolvedLatitude: place.latitude,
        resolvedLongitude: place.longitude,
        distanceKm: haversineKm(
          latitude,
          longitude,
          place.latitude,
          place.longitude,
        ),
        rating: place.rating,
        photoReference: place.photoReference,
      } satisfies RecommendationItem;
    } catch (error) {
      console.error(`Unable to resolve ${item.name} with Places:`, error);
      return null;
    }
  }));
  return resolved
    .filter((item): item is RecommendationItem => item != null)
    .map((item, index) => ({ ...item, rank: index + 1 }));
}

interface PlaceResult {
  id: string;
  formattedAddress: string | null;
  latitude: number;
  longitude: number;
  rating: number | null;
  photoReference: string | null;
}

async function getPlaceById(id: string, apiKey: string): Promise<PlaceResult | null> {
  const response = await fetch(
    `https://places.googleapis.com/v1/places/${encodeURIComponent(id)}`,
    {
      headers: {
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask":
          "id,formattedAddress,location,rating,photos",
      },
    },
  );
  const data = await response.json();
  if (!response.ok) throw new Error(data?.error?.message ?? "Places lookup failed.");
  return parsePlace(data);
}

async function searchPlace(
  name: string,
  address: string | null,
  latitude: number,
  longitude: number,
  radiusKm: number,
  apiKey: string,
): Promise<PlaceResult | null> {
  const response = await fetch(
    "https://places.googleapis.com/v1/places:searchText",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask":
          "places.id,places.formattedAddress,places.location,places.rating,places.photos",
      },
      body: JSON.stringify({
        textQuery: [name, address].filter(Boolean).join(", "),
        maxResultCount: 3,
        locationBias: {
          circle: {
            center: { latitude, longitude },
            radius: clamp(radiusKm * 1000, 100, 50000),
          },
        },
      }),
    },
  );
  const data = await response.json();
  if (!response.ok) throw new Error(data?.error?.message ?? "Places search failed.");
  const places = Array.isArray(data?.places) ? data.places : [];
  return places.length === 0 ? null : parsePlace(places[0]);
}

function parsePlace(value: Record<string, any>): PlaceResult | null {
  const resolvedLatitude = Number(value?.location?.latitude);
  const resolvedLongitude = Number(value?.location?.longitude);
  const id = optionalString(value?.id);
  if (!id || !Number.isFinite(resolvedLatitude) ||
    !Number.isFinite(resolvedLongitude)) return null;
  const photos = Array.isArray(value?.photos) ? value.photos : [];
  const rating = Number(value?.rating);
  return {
    id,
    formattedAddress: optionalString(value?.formattedAddress),
    latitude: resolvedLatitude,
    longitude: resolvedLongitude,
    rating: Number.isFinite(rating) ? rating : null,
    photoReference: optionalString(photos[0]?.name),
  };
}

async function reserveAiAttempt(
  supabase: SupabaseAdminClient,
  cacheKey: string,
  modelName: string,
) {
  const start = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { count, error } = await supabase
    .from("nearby_recommendation_ai_usage")
    .select("id", { count: "exact", head: true })
    .gte("attempted_at", start);
  if (error) throw error;
  if ((count ?? 0) >= DAILY_CALL_BUDGET) {
    throw new GeminiRequestError(429, "The shared AI budget has been reached.");
  }
  const { error: insertError } = await supabase
    .from("nearby_recommendation_ai_usage")
    .insert({ cache_key: cacheKey, model_name: modelName });
  if (insertError) throw insertError;
}

async function saveRecommendationLog({
  supabase,
  userId,
  latitude,
  longitude,
  currentAttractionId,
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
  currentAttractionId: string;
  preferences: Preferences;
  prompt: string;
  recommendations: RecommendationItem[];
  cacheKey: string;
  modelName: string;
  latencyMs: number;
}) {
  const { error } = await supabase.from("recommendation_logs").insert({
    user_id: userId,
    recommendation_type: "ar",
    current_latitude: latitude,
    current_longtitude: longitude,
    current_attraction_id: currentAttractionId,
    preferences_snapshot: preferences,
    prompt,
    response_json: { recommendations },
    context_hash: cacheKey,
    status: "success",
    model_name: modelName,
    latency_ms: latencyMs,
  });
  if (error) console.error("AR recommendation log error:", error);
}

async function recommendationResponse(
  recommendations: RecommendationItem[],
  meta: {
    source: string;
    modelName: string;
    usedDefaultPreferences: boolean;
  },
  supabaseUrl: string,
  signingSecret: string,
): Promise<Response> {
  return Response.json({
    recommendations: await Promise.all(recommendations.map(async (item) => ({
      attraction_id: item.attractionId,
      marker_id: item.markerId,
      place_id: item.placeId,
      name: item.resolvedName,
      category: item.category,
      address: item.resolvedAddress,
      summary: item.summary,
      reason: item.reason,
      relationship: item.relationship,
      rank: item.rank,
      latitude: item.resolvedLatitude,
      longitude: item.resolvedLongitude,
      distance_km: Number(item.distanceKm.toFixed(2)),
      ...(item.rating == null ? {} : { rating: item.rating }),
      ...(item.photoReference == null ? {} : {
        image_url: await buildSignedPhotoUrl(
          supabaseUrl,
          item.photoReference,
          signingSecret,
        ),
      }),
    }))),
    meta: {
      source: meta.source,
      model_name: meta.modelName,
      returned_count: recommendations.length,
      used_default_preferences: meta.usedDefaultPreferences,
      prompt_version: PROMPT_VERSION,
    },
  });
}

function validateStoredRecommendations(value: unknown): RecommendationItem[] {
  if (!Array.isArray(value)) return [];
  return value.filter((row) => row && typeof row === "object").map((raw) => {
    const row = raw as Record<string, any>;
    return {
      attractionId: optionalString(row.attractionId) ?? "",
      markerId: optionalString(row.markerId) ?? "",
      siteId: optionalString(row.siteId),
      name: optionalString(row.name) ?? "AR attraction",
      summary: optionalString(row.summary) ?? "",
      labels: cleanArray(row.labels),
      category: optionalString(row.category) ?? "AR attraction",
      latitude: Number(row.latitude),
      longitude: Number(row.longitude),
      distanceKm: Number(row.distanceKm),
      updatedAt: optionalString(row.updatedAt) ?? "",
      address: optionalString(row.address),
      googlePlaceId: optionalString(row.googlePlaceId),
      reason: optionalString(row.reason) ?? "Recommended for your visit.",
      relationship: optionalString(row.relationship) ?? "Complementary experience",
      rank: Number(row.rank),
      placeId: optionalString(row.placeId) ?? "",
      resolvedName: optionalString(row.resolvedName) ?? "AR attraction",
      resolvedAddress: optionalString(row.resolvedAddress) ?? "Address unavailable",
      resolvedLatitude: Number(row.resolvedLatitude),
      resolvedLongitude: Number(row.resolvedLongitude),
      rating: row.rating == null ? null : Number(row.rating),
      photoReference: optionalString(row.photoReference),
    };
  }).filter((item) =>
    item.attractionId && item.markerId && item.placeId &&
    Number.isFinite(item.resolvedLatitude) &&
    Number.isFinite(item.resolvedLongitude)
  ).slice(0, 3);
}

async function buildSignedPhotoUrl(
  supabaseUrl: string,
  resource: string,
  secret: string,
): Promise<string> {
  const expires = Math.floor(Date.now() / 1000) + 25 * 60 * 60;
  const signature = await hmacSha256(`${resource}|${expires}`, secret);
  const url = new URL(`${supabaseUrl}/functions/v1/place-photo`);
  url.searchParams.set("resource", resource);
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
  let binary = "";
  for (const byte of new Uint8Array(signature)) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

function stablePreferences(preferences: Preferences): string {
  return JSON.stringify(Object.fromEntries(
    Object.entries(preferences).map(([key, values]) => [
      key,
      [...new Set(values.map((value) => value.trim().toLowerCase()))].sort(),
    ]),
  ));
}

function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number) {
  const toRadians = (value: number) => value * Math.PI / 180;
  const dLat = toRadians(lat2 - lat1);
  const dLon = toRadians(lon2 - lon1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRadians(lat1)) * Math.cos(toRadians(lat2)) *
      Math.sin(dLon / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function cleanArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map((item) => String(item).trim()).filter(Boolean))]
    .sort((a, b) => a.localeCompare(b));
}

function optionalString(value: unknown): string | null {
  const text = value == null ? "" : String(value).trim();
  return text || null;
}

function truncate(value: string, maximum: number): string {
  return value.length <= maximum ? value : `${value.slice(0, maximum - 1)}…`;
}

function normaliseName(value: string): string {
  return value.toLowerCase().replaceAll(/[^a-z0-9]/g, "");
}

function bucket(value: number): string {
  return (Math.round(value * 100) / 100).toFixed(2);
}

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(maximum, Math.max(minimum, value));
}

function removeCodeFences(value: string): string {
  return value.replace(/^```json\s*/i, "").replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "").trim();
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Required environment variable ${name} is missing.`);
  return value;
}

function numberFromEnv(name: string, fallback: number): number {
  const value = Number(Deno.env.get(name));
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

class GeminiRequestError extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}
