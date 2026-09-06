import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const YOUTUBE_API_KEY = Deno.env.get("YOUTUBE_API_KEY");

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !YOUTUBE_API_KEY) {
  throw new Error("Missing SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, or YOUTUBE_API_KEY");
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

/* =========================================================
   YOUTUBE SEARCH — find candidate videos
   ========================================================= */

interface YouTubeCandidate {
  videoId: string;
  title: string;
  url: string;
}

async function searchYouTube(query: string, maxResults = 6): Promise<YouTubeCandidate[]> {
  const params = new URLSearchParams({
    key: YOUTUBE_API_KEY!,
    q: query,
    part: "snippet",
    type: "video",
    maxResults: String(maxResults),
    safeSearch: "strict",
    videoEmbeddable: "true", // pre-filters obviously non-embeddable results server-side
  });

  const res = await fetch(`https://www.googleapis.com/youtube/v3/search?${params}`);

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`YouTube search failed (${res.status}): ${errText.slice(0, 500)}`);
  }

  const data = await res.json();

  return (data.items ?? [])
    .filter((item: { id?: { videoId?: string } }) => item.id?.videoId)
    .map((item: { id: { videoId: string }; snippet: { title: string } }) => ({
      videoId: item.id.videoId,
      title: item.snippet.title,
      url: `https://www.youtube.com/watch?v=${item.id.videoId}`,
    }));
}

/* =========================================================
   OEMBED VALIDATION — confirm a candidate is actually playable
   ========================================================= */

async function isPlayable(url: string): Promise<boolean> {
  try {
    const params = new URLSearchParams({ url, format: "json" });
    const res = await fetch(`https://www.youtube.com/oembed?${params}`);
    // 200 = public + embeddable. 401/404/400 = private, deleted, or
    // embedding disabled — not usable regardless of what the search
    // API said about it.
    return res.ok;
  } catch {
    // Network error during validation — treat as not-playable rather
    // than throwing, so one flaky check doesn't kill the whole row.
    return false;
  }
}

/* =========================================================
   FIND PRIMARY + BACKUP for one attraction
   ========================================================= */

async function findVideosForAttraction(
  attractionName: string
): Promise<{ primary: string | null; backup: string | null }> {
  const query = `${attractionName} Malaysia tour guide history`;
  const candidates = await searchYouTube(query);

  console.log(`SEARCH "${query}": ${candidates.length} candidate(s)`);

  const confirmed: string[] = [];

  for (const candidate of candidates) {
    if (confirmed.length >= 2) break;

    const playable = await isPlayable(candidate.url);
    console.log(`  CHECK ${candidate.url} ("${candidate.title}"): ${playable ? "PLAYABLE" : "not playable"}`);

    if (playable) confirmed.push(candidate.url);
  }

  return {
    primary: confirmed[0] ?? null,
    backup: confirmed[1] ?? null,
  };
}

/* =========================================================
   UPDATE DATABASE
   ========================================================= */

async function updateAttractionVideo(
  attractionId: string,
  primary: string | null,
  backup: string | null
) {
  const status = primary ? "ok" : "error: no playable video found";

  const { error } = await supabase
    .from("Attraction")
    .update({
      video_url: primary,
      video_url_backup: backup,
      last_video_status: status,
    })
    .eq("attraction_id", attractionId);

  if (error) {
    throw new Error(`Supabase UPDATE failed: ${error.message}`);
  }
}

/* =========================================================
   PROCESS ONE ROW
   ========================================================= */

async function processAttraction(row: { attraction_id: string; name: string | null }) {
  const id = row.attraction_id;

  try {
    console.log(`========================================`);
    console.log(`PROCESSING VIDEO: ${row.name ?? id}`);

    if (!row.name?.trim()) {
      throw new Error("name is missing — can't build a search query");
    }

    const { primary, backup } = await findVideosForAttraction(row.name.trim());

    await updateAttractionVideo(id, primary, backup);

    console.log(`RESULT: primary=${primary ?? "none"} backup=${backup ?? "none"}`);

    return { id, name: row.name, status: primary ? "ok" : "no video found", primary, backup };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error(`PROCESS ERROR ${id}:`, errorMessage);

    await supabase
      .from("Attraction")
      .update({ last_video_status: `error: ${errorMessage.slice(0, 450)}` })
      .eq("attraction_id", id);

    return { id, name: row.name, status: `error: ${errorMessage}` };
  }
}

/* =========================================================
   BATCH PROCESSING
   ========================================================= */

// YouTube search costs 100 quota units per call (10,000/day default
// quota => ~100 searches/day possible). Keep concurrency modest —
// this is shared against that budget, not just wall-clock time.
const BATCH_CONCURRENCY = 3;

async function processAllAttractions(rows: { attraction_id: string; name: string | null }[]) {
  const results: Awaited<ReturnType<typeof processAttraction>>[] = [];

  for (let i = 0; i < rows.length; i += BATCH_CONCURRENCY) {
    const batch = rows.slice(i, i + BATCH_CONCURRENCY);
    console.log(
      `BATCH ${Math.floor(i / BATCH_CONCURRENCY) + 1}: processing ${batch.length} attraction(s) (${i + 1}-${i + batch.length} of ${rows.length})`
    );
    const batchResults = await Promise.all(batch.map((row) => processAttraction(row)));
    results.push(...batchResults);
  }

  const succeeded = results.filter((r) => r.status === "ok").length;
  console.log(`BATCH COMPLETE: ${succeeded} succeeded, ${results.length - succeeded} failed, ${results.length} total`);
  console.log("BATCH RESULTS:", JSON.stringify(results));

  return results;
}

/* =========================================================
   EDGE FUNCTION
   ========================================================= */

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({}));
    const requestedId = body?.attraction_id;

    let query = supabase.from("Attraction").select("attraction_id, name").not("name", "is", null);
    if (requestedId) query = query.eq("attraction_id", requestedId);

    const { data, error } = await query;
    if (error) throw new Error(`Attraction query failed: ${error.message}`);

    if (!data || data.length === 0) {
      return new Response(JSON.stringify({ success: true, message: "No attraction found" }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    if (requestedId) {
      const result = await processAttraction(data[0]);
      return new Response(JSON.stringify({ success: true, result }), {
        status: result.status === "ok" ? 200 : 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    console.log(`BATCH MODE: ${data.length} attraction(s) queued for video lookup`);
    EdgeRuntime.waitUntil(processAllAttractions(data));

    return new Response(
      JSON.stringify({
        success: true,
        message: `Started video lookup for ${data.length} attraction(s) in the background`,
        count: data.length,
      }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message);
    return new Response(JSON.stringify({ success: false, error: message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});