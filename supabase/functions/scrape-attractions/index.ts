import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get(
  "SUPABASE_SERVICE_ROLE_KEY"
);
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");

const delay = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/* =========================================================
   MODEL FALLBACK CHAIN
   ========================================================= */

// Ordered from newest/most capable to oldest/cheapest. When the current
// model gets rate-limited (429), we don't just sit and wait on it —
// each Gemini model has its own separate RPM/RPD quota, so hopping to
// the next model in this list is usually much faster than backing off.
// Waiting is now the LAST resort, used only once every model in the
// chain has been tried and is still limited.
//
// Model IDs current as of Aug/Sep 2026 — note there is no 3.5/3.6/3.7
// Pro; the Pro flagship is still gemini-3.1-pro-preview. If Google
// ships new model IDs later, just add them here.
const MODEL_FALLBACK_CHAIN = [
  "gemini-3.6-flash",
  "gemini-3.5-flash",
  "gemini-3.5-flash-lite",
  "gemini-3.1-flash-lite",
  "gemini-3.1-pro-preview",
];

// Shared across rows for the lifetime of this isolate (best-effort —
// a freshly spun-up isolate just starts back at index 0). Once a model
// is found to be rate-limited we keep using the next one for
// subsequent rows too, instead of re-discovering the same 429 on every
// single row.
let currentModelIndex = 0;

function getCurrentModel(): string {
  return (
    MODEL_FALLBACK_CHAIN[currentModelIndex] ??
    MODEL_FALLBACK_CHAIN[MODEL_FALLBACK_CHAIN.length - 1]
  );
}

// Moves to the next model in the chain and returns it, or returns null
// if we've already reached the last model (nothing left to hop to).
function advanceModel(): string | null {
  if (currentModelIndex < MODEL_FALLBACK_CHAIN.length - 1) {
    currentModelIndex++;
    const next = getCurrentModel();
    console.log(`MODEL FALLBACK: switching to ${next}`);
    return next;
  }
  return null;
}

if (
  !SUPABASE_URL ||
  !SUPABASE_SERVICE_ROLE_KEY ||
  !GEMINI_API_KEY
) {
  throw new Error(
    "Missing SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, or GEMINI_API_KEY"
  );
}

const supabase = createClient(
  SUPABASE_URL,
  SUPABASE_SERVICE_ROLE_KEY
);

/* =========================================================
   RETRY / RATE-LIMIT HELPERS
   ========================================================= */

// Thrown specifically for Gemini 429s so withRetry can tell the
// difference between "retry this" and "fail for real".
class GeminiRateLimitError extends Error {
  retryDelayMs?: number;
  constructor(message: string, retryDelayMs?: number) {
    super(message);
    this.name = "GeminiRateLimitError";
    this.retryDelayMs = retryDelayMs;
  }
}

// Gemini's 429 body often includes a RetryInfo detail telling you
// exactly how long to wait, e.g. { "@type": "...RetryInfo", "retryDelay": "17s" }.
// If present, honor it instead of guessing.
function parseRetryDelayMs(errorBody: string): number | undefined {
  try {
    const parsed = JSON.parse(errorBody);
    const details = parsed?.error?.details ?? [];
    const retryInfo = details.find((d: any) =>
      typeof d?.["@type"] === "string" && d["@type"].includes("RetryInfo")
    );
    const retryDelayStr: string | undefined = retryInfo?.retryDelay;
    if (retryDelayStr) {
      const seconds = parseFloat(retryDelayStr.replace(/s$/i, ""));
      if (!Number.isNaN(seconds)) return seconds * 1000;
    }
  } catch {
    // Body wasn't JSON or didn't have the expected shape — fall back
    // to exponential backoff instead of failing to parse.
  }
  return undefined;
}

async function withRetry<T>(
  fn: () => Promise<T>,
  { maxAttempts = 5, baseDelayMs = 5000 }: { maxAttempts?: number; baseDelayMs?: number } = {}
): Promise<T> {
  let attempt = 0;
  while (true) {
    attempt++;
    try {
      return await fn();
    } catch (err) {
      const isRateLimit = err instanceof GeminiRateLimitError;

      if (!isRateLimit || attempt >= maxAttempts) {
        throw err;
      }

      const jitter = Math.random() * 1000;
      const backoff =
        err.retryDelayMs ?? baseDelayMs * 2 ** (attempt - 1);
      const wait = backoff + jitter;

      console.log(
        `GEMINI RATE LIMITED (attempt ${attempt}/${maxAttempts}) — waiting ${Math.round(
          wait
        )}ms before retry`
      );

      await delay(wait);
    }
  }
}

/* =========================================================
   HTML CLEANING
   ========================================================= */

function decodeHtmlEntities(text: string): string {
  return text
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/&apos;/gi, "'")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&#(\d+);/g, (_, code) =>
      String.fromCharCode(Number(code))
    )
    .replace(/&#x([0-9a-f]+);/gi, (_, code) =>
      String.fromCharCode(parseInt(code, 16))
    );
}

function htmlToText(html: string): string {
  let content = html;

  // Remove things that are not article content.
  content = content.replace(
    /<(script|style|noscript|template|svg|canvas|iframe|form|nav|footer|header|aside)[\s\S]*?<\/\1>/gi,
    " "
  );

  // Wikipedia's main article body.
  const wikipediaArticle =
    content.match(
      /<div[^>]+id=["']mw-content-text["'][^>]*>([\s\S]*?)<\/div>\s*<\/main>/i
    );

  // Generic article/main fallback.
  const article =
    wikipediaArticle?.[1] ||
    content.match(/<main\b[^>]*>([\s\S]*?)<\/main>/i)?.[1] ||
    content.match(/<article\b[^>]*>([\s\S]*?)<\/article>/i)?.[1] ||
    content;

  content = article;

  // Remove tables, metadata and other large non-prose sections.
  content = content.replace(
    /<(table|figure|figcaption|style|script|noscript)[\s\S]*?<\/\1>/gi,
    " "
  );

  // Preserve paragraph boundaries.
  content = content.replace(
    /<\/(p|div|section|li|h1|h2|h3|h4|h5|h6|br)>/gi,
    "\n"
  );

  // Remove remaining tags.
  content = content.replace(/<[^>]+>/g, " ");

  content = decodeHtmlEntities(content);

  return content
    .replace(/\r/g, "")
    .replace(/[ \t]+/g, " ")
    .replace(/\n\s+/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

async function scrapePage(url: string): Promise<string> {
  console.log(`SCRAPE START: ${url}`);

  const response = await fetch(url, {
    redirect: "follow",
    headers: {
      "User-Agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/151.0.0.0 Safari/537.36",
      "Accept":
        "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language": "en-US,en;q=0.9",
    },
  });

  if (!response.ok) {
    throw new Error(
      `Scrape failed: ${response.status} ${response.statusText}`
    );
  }

  const html = await response.text();

  console.log(`HTML LENGTH: ${html.length}`);

  const text = htmlToText(html);

  console.log(`EXTRACTED TEXT LENGTH: ${text.length}`);

  if (!text) {
    throw new Error("No readable content extracted");
  }

  // CRITICAL:
  // Do not send the entire scraped page to Gemini.
  const MAX_GEMINI_INPUT = 12000;

  const limitedText = text.slice(0, MAX_GEMINI_INPUT);

  console.log(
    `TEXT SENT TO GEMINI: ${limitedText.length} characters`
  );

  return limitedText;
}

/* =========================================================
   GEMINI
   ========================================================= */

async function callGeminiOnce(
  model: string,
  attractionName: string,
  sourceUrl: string,
  rawText: string
): Promise<string> {
  const prompt = `
You are an enthusiastic tour guide writing audio narration
for a heritage AR application.

Attraction:
${attractionName}

Source URL:
${sourceUrl}

SOURCE CONTENT:
${rawText}

Write ONE paragraph introducing ${attractionName}.

Requirements:
- Write between 50 and 80 words.
- Aim for approximately 60 words.
- Use only facts from the source content.
- Do not invent information.
- Make it engaging and natural for spoken narration.
- Focus on historical, cultural, architectural, or important facts.
- No heading.
- No bullet points.
- No markdown.
- No explanation.
- Return ONLY the narration.
`;

  console.log(`GEMINI REQUEST MODEL: ${model}`);

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${encodeURIComponent(
      GEMINI_API_KEY
    )}`,
    {
      method: "POST",

      headers: {
        "Content-Type": "application/json",
      },

      body: JSON.stringify({
        contents: [
          {
            role: "user",
            parts: [
              {
                text: prompt,
              },
            ],
          },
        ],

        generationConfig: {
          maxOutputTokens: 300,

          thinkingConfig: {
            thinkingLevel: "minimal",
          },
        },
      }),
    }
  );

  if (!response.ok) {
    const errorText = await response.text();

    if (response.status === 429) {
      throw new GeminiRateLimitError(
        `Gemini rate limited (429): ${errorText.slice(0, 500)}`,
        parseRetryDelayMs(errorText)
      );
    }

    throw new Error(
      `Gemini error (${response.status}): ${errorText.slice(0, 1000)}`
    );
  }

  const data = await response.json();

  // IMPORTANT: log the candidate metadata
  // so we know exactly why Gemini stopped.
  const candidate = data?.candidates?.[0];

  console.log(
    "GEMINI FINISH REASON:",
    candidate?.finishReason
  );

  console.log(
    "GEMINI FINISH MESSAGE:",
    candidate?.finishMessage
  );

  console.log(
    "GEMINI TOKEN COUNT:",
    candidate?.tokenCount
  );

  console.log(
    "GEMINI SAFETY:",
    JSON.stringify(candidate?.safetyRatings ?? [])
  );

  if (!candidate) {
    throw new Error(
      "Gemini returned no candidate"
    );
  }

  if (
    candidate.finishReason &&
    candidate.finishReason !== "STOP"
  ) {
    throw new Error(
      `Gemini stopped with ${candidate.finishReason}: ${
        candidate.finishMessage ?? ""
      }`
    );
  }

  const summary =
    candidate?.content?.parts
      ?.filter(
        (part: { text?: string; thought?: boolean }) =>
          typeof part.text === "string" &&
          !part.thought
      )
      ?.map(
        (part: { text: string }) =>
          part.text
      )
      ?.join(" ")
      ?.replace(/\s+/g, " ")
      ?.trim();

  if (!summary) {
    throw new Error(
      "Gemini returned no visible text"
    );
  }

  const wordCount =
    summary.split(/\s+/).filter(Boolean).length;

  console.log(
    `GEMINI VISIBLE OUTPUT: ${wordCount} words`
  );

  // Gemini sometimes returns STOP with a natural-language refusal
  // instead of an error (e.g. "I cannot fulfill this request because
  // the source content doesn't mention X"). That's a valid STOP from
  // the API's perspective but not usable narration — without this
  // check it gets saved to attraction_content and marked "ok". Catch
  // the common refusal phrasing so it's treated as a real failure and
  // retried/reported instead of silently corrupting the content column.
  const looksLikeRefusal =
    /^i (cannot|can't|am unable to|won't)\b/i.test(summary) ||
    /does not contain (any )?(facts|information)/i.test(summary);

  if (looksLikeRefusal) {
    throw new Error(
      `Gemini declined to generate narration (likely source content mismatch): ${summary.slice(
        0,
        200
      )}`
    );
  }

  return summary;
}

// Public entry point. Tries the current model in MODEL_FALLBACK_CHAIN;
// on a 429, hops to the next model immediately (no wait, since it has
// its own separate quota) rather than backing off on the same model.
// Only once every model in the chain is rate-limited does it fall back
// to timed exponential backoff on the last model tried.
async function summarizeWithGemini(
  attractionName: string,
  sourceUrl: string,
  rawText: string
): Promise<string> {
  while (true) {
    const model = getCurrentModel();

    try {
      return await callGeminiOnce(model, attractionName, sourceUrl, rawText);
    } catch (err) {
      if (!(err instanceof GeminiRateLimitError)) {
        // Non-rate-limit errors (bad content, safety block, etc.)
        // shouldn't trigger a model hop — surface them as-is.
        throw err;
      }

      console.log(`GEMINI RATE LIMITED on ${model}`);

      const nextModel = advanceModel();
      if (nextModel) {
        continue; // immediately retry on the next model in the chain
      }

      // Every model in the chain is rate-limited. Fall back to timed
      // exponential backoff on whichever model we ended on.
      console.log(
        "MODEL FALLBACK EXHAUSTED — falling back to timed backoff"
      );
      return withRetry(
        () => callGeminiOnce(model, attractionName, sourceUrl, rawText),
        { maxAttempts: 5, baseDelayMs: 8000 }
      );
    }
  }
}

/* =========================================================
   UPDATE DATABASE
   ========================================================= */

async function updateAttraction(
  attractionId: string,
  summary: string
) {
  console.log(
    `DB UPDATE START: ${attractionId}`
  );

  const updatedAt =
    new Date().toISOString();

  const { data, error } = await supabase
    .from("Attraction")
    .update({
      attraction_content: summary,
      updated_at: updatedAt,
      last_scrape_status: "ok",
    })
    .eq(
      "attraction_id",
      attractionId
    )
    .select(
      "attraction_id, name, attraction_content, updated_at, last_scrape_status"
    )
    .single();

  if (error) {
    console.error(
      "DB UPDATE ERROR:",
      error
    );

    throw new Error(
      `Supabase UPDATE failed: ${error.message}`
    );
  }

  if (!data) {
    throw new Error(
      "Supabase UPDATE returned no row"
    );
  }

  console.log(
    "DB UPDATE SUCCESS:",
    JSON.stringify(data)
  );

  return data;
}

/* =========================================================
   VERIFY DATABASE
   ========================================================= */

async function verifyAttraction(
  attractionId: string
) {
  console.log(
    `DB VERIFY START: ${attractionId}`
  );

  const { data, error } = await supabase
    .from("Attraction")
    .select(
      "attraction_id, name, source_url, attraction_content, updated_at, last_scrape_status"
    )
    .eq(
      "attraction_id",
      attractionId
    )
    .maybeSingle();

  if (error) {
    throw new Error(
      `Verification failed: ${error.message}`
    );
  }

  if (!data) {
    throw new Error(
      `Attraction ${attractionId} could not be found after update`
    );
  }

  console.log(
    "DB VERIFY RESULT:",
    JSON.stringify(data)
  );

  return data;
}

/* =========================================================
   PROCESS ONE ROW
   ========================================================= */

async function processAttraction(row: {
  attraction_id: string;
  name: string | null;
  source_url: string | null;
}) {
  const id = row.attraction_id;

  try {
    console.log(
      `========================================`
    );

    console.log(
      `PROCESSING: ${row.name ?? id}`
    );

    console.log(
      `ID: ${id}`
    );

    console.log(
      `SOURCE URL: ${row.source_url}`
    );

    if (!row.source_url?.trim()) {
      throw new Error(
        "source_url is missing"
      );
    }

    const sourceUrl =
      row.source_url.trim();

    // 1. SCRAPE
    const rawText =
      await scrapePage(sourceUrl);

    // 2. GEMINI (internally retries on 429)
    const summary =
      await summarizeWithGemini(
        row.name ?? "this attraction",
        sourceUrl,
        rawText
      );

    console.log(
      `SUMMARY: ${summary}`
    );

    // 3. UPDATE
    const updated =
      await updateAttraction(
        id,
        summary
      );

    // 4. VERIFY
    const verified =
      await verifyAttraction(id);

    return {
      id,
      name: row.name,
      source_url: sourceUrl,
      status: "ok",

      updatedContent:
        updated.attraction_content,

      verifiedContent:
        verified.attraction_content,

      updatedAt:
        verified.updated_at,
    };

  } catch (error) {

    const errorMessage =
      error instanceof Error
        ? error.message
        : String(error);

    console.error(
      `PROCESS ERROR ${id}:`,
      errorMessage
    );

    // Try to save the error itself.
    const { error: statusError } =
      await supabase
        .from("Attraction")
        .update({
          last_scrape_status:
            `error: ${errorMessage.slice(0, 450)}`,

          updated_at:
            new Date().toISOString(),
        })
        .eq(
          "attraction_id",
          id
        );

    if (statusError) {
      console.error(
        "Could not save error status:",
        statusError
      );
    }

    return {
      id,
      name: row.name,
      source_url: row.source_url,
      status:
        `error: ${errorMessage}`,
    };
  }
}

/* =========================================================
   BATCH PROCESSING (a bounded chunk of attractions)
   ========================================================= */

// How many attractions to process per invocation. Each Gemini call is
// taking ~30-47s in practice, so this must stay small enough that the
// WHOLE chunk finishes comfortably inside Supabase's background-task
// wall-clock budget (150s Free / 400s Pro) — see SOFT_DEADLINE_MS below.
// This is now a per-invocation cap, not the total attraction count:
// with 28 rows to refresh, this function will be called repeatedly
// (see cron note near the bottom) and will work through a few more
// rows each time.
const BATCH_CONCURRENCY = 1;

// Minimum spacing between the *start* of consecutive Gemini calls, to
// stay well under free-tier RPM limits.
const MIN_GAP_BETWEEN_ROWS_MS = 4500;

// Hard safety cutoff for how long we let ourselves keep starting new
// rows within a single invocation. Set comfortably below the platform's
// actual kill time (150s Free / 400s Pro) so we can return a clean,
// fully-recorded result instead of being killed mid-row with nothing
// written to the DB for whatever was in flight.
const SOFT_DEADLINE_MS = 120_000; // 2 min — safe under the 150s Free budget

// How many rows batch mode pulls PER INVOCATION (see the query in
// Deno.serve). At ~30-45s per Gemini call, ~4 rows plus inter-row
// delays fits comfortably inside SOFT_DEADLINE_MS with margin to spare.
// Tune this up if you upgrade to Pro (400s budget) or if your observed
// per-row latency comes down.
const PROCESS_LIMIT_PER_INVOCATION = 4;

async function processAllAttractions(
  rows: {
    attraction_id: string;
    name: string | null;
    source_url: string | null;
  }[]
) {
  const results: Awaited<ReturnType<typeof processAttraction>>[] = [];
  const startedAt = Date.now();

  for (let i = 0; i < rows.length; i += BATCH_CONCURRENCY) {
    const elapsed = Date.now() - startedAt;

    if (elapsed > SOFT_DEADLINE_MS) {
      console.log(
        `SOFT DEADLINE HIT after ${elapsed}ms — stopping early with ${i}/${rows.length} attempted. Remaining rows will be picked up on the next invocation.`
      );
      break;
    }

    const batch = rows.slice(i, i + BATCH_CONCURRENCY);

    console.log(
      `BATCH ${Math.floor(i / BATCH_CONCURRENCY) + 1}: processing ${batch.length} attraction(s) (${i + 1}-${i + batch.length} of ${rows.length})`
    );

    const batchResults = await Promise.all(
      batch.map((row) => processAttraction(row))
    );

    results.push(...batchResults);

    if (i + BATCH_CONCURRENCY < rows.length) {
      console.log(
        `Waiting ${MIN_GAP_BETWEEN_ROWS_MS}ms to avoid Gemini API rate limits...`
      );
      await delay(MIN_GAP_BETWEEN_ROWS_MS);
    }
  }

  const succeeded = results.filter((r) => r.status === "ok").length;
  const failed = results.length - succeeded;

  console.log(
    `CHUNK COMPLETE: ${succeeded} succeeded, ${failed} failed, ${results.length} of ${rows.length} attempted this invocation`
  );
  console.log("CHUNK RESULTS:", JSON.stringify(results));

  return results;
}

/* =========================================================
   EDGE FUNCTION
   ========================================================= */

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({}));

    const requestedId = body?.attraction_id;

    let query = supabase
      .from("Attraction")
      .select("attraction_id, name, source_url, updated_at")
      .not("source_url", "is", null)
      .neq("source_url", "");

    if (requestedId) {
      query = query.eq("attraction_id", requestedId);
    } else {
      // Batch mode: only pull a bounded CHUNK per invocation, oldest
      // (or never-updated) rows first. Each Gemini call takes ~30-45s
      // in practice, so a single invocation cannot safely fit all rows
      // before Supabase's background-task wall-clock budget (150s Free /
      // 400s Pro) kills the isolate mid-row. Ordering by updated_at
      // ascending (nulls first) means: whatever this invocation doesn't
      // get to will simply be at the front of the queue next time this
      // function is called — no separate offset/cursor bookkeeping
      // needed. Pair this with a scheduler that calls the function
      // every 2-3 minutes (see note below) until the whole table is
      // refreshed.
      query = query
        .order("updated_at", { ascending: true, nullsFirst: true })
        .limit(PROCESS_LIMIT_PER_INVOCATION);
    }

    const { data, error } = await query;

    if (error) {
      throw new Error(
        `Attraction query failed: ${error.message}`
      );
    }

    if (!data || data.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          message: "No attraction found",
        }),
        {
          headers: {
            "Content-Type": "application/json",
          },
        }
      );
    }

    // Single-attraction mode (e.g. { "attraction_id": "..." } in the
    // request body): process it synchronously and return the full result.
    if (requestedId) {
      const result = await processAttraction(data[0]);

      return new Response(
        JSON.stringify({ success: true, result }),
        {
          status: result.status === "ok" ? 200 : 500,
          headers: {
            "Content-Type": "application/json",
          },
        }
      );
    }

    // Batch mode (no attraction_id given): this pulls up to
    // PROCESS_LIMIT_PER_INVOCATION rows, oldest-updated first, and
    // processes just that chunk in the background. It intentionally
    // does NOT try to process the whole table in one call — see the
    // comment on PROCESS_LIMIT_PER_INVOCATION and the query above for
    // why. Call this function repeatedly (e.g. a pg_cron job hitting it
    // every 2-3 minutes) until every row's updated_at is recent; each
    // call will naturally pick up whatever wasn't refreshed yet.
    console.log(`BATCH MODE: ${data.length} attraction(s) queued this invocation`);

    EdgeRuntime.waitUntil(processAllAttractions(data));

    return new Response(
      JSON.stringify({
        success: true,
        message: `Started processing ${data.length} attraction(s) in the background (chunked — call again to continue working through the table)`,
        count: data.length,
      }),
      {
        headers: {
          "Content-Type": "application/json",
        },
      }
    );
  } catch (error) {
    const message =
      error instanceof Error
        ? error.message
        : String(error);

    console.error(message);

    return new Response(
      JSON.stringify({
        success: false,
        error: message,
      }),
      {
        status: 500,
        headers: {
          "Content-Type": "application/json",
        },
      }
    );
  }
});