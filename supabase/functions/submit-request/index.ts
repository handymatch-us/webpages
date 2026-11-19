// HandyMatch: receives the homeowner request form and saves it.
//
// Public endpoint (no login), so it validates everything itself:
// allowed website origins only, a hidden spam field, strict field checks,
// and a per-phone limit. It writes with the service role key, which never
// leaves the server.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const ALLOWED_ORIGINS = new Set([
  "https://handymatch-us.github.io",
  "https://handymatch.us",
  "https://www.handymatch.us",
]);

const SERVICES: Record<string, string> = {
  "General handyman repairs": "handyman",
  "TV and shelf mounting": "tv_mounting",
  "Drywall repair": "drywall",
  "Furniture assembly": "furniture_assembly",
  "Garage door repair": "garage_door",
  "Appliance repair": "appliance_repair",
};

const TIMINGS: Record<string, string> = {
  "As soon as possible": "asap",
  "This week": "this_week",
  "Flexible": "flexible",
};

const MAX_REQUESTS_PER_PHONE_PER_DAY = 5;

function corsHeaders(origin: string | null): Record<string, string> {
  const allowed = origin && (ALLOWED_ORIGINS.has(origin) || /^http:\/\/localhost(:\d+)?$/.test(origin));
  return {
    "Access-Control-Allow-Origin": allowed ? origin! : "https://handymatch-us.github.io",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "content-type",
    "Vary": "Origin",
  };
}

function reply(status: number, body: unknown, origin: string | null) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
  });
}

function text(value: unknown, max: number): string {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

// US phone numbers only: returns +1XXXXXXXXXX, or null if invalid.
function normalizePhone(value: string): string | null {
  let digits = value.replace(/\D/g, "");
  if (digits.length === 11 && digits.startsWith("1")) digits = digits.slice(1);
  if (digits.length !== 10 || /^[01]/.test(digits)) return null;
  return "+1" + digits;
}

Deno.serve(async (req) => {
  const origin = req.headers.get("origin");

  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(origin) });
  if (req.method !== "POST") return reply(405, { error: "Use POST" }, origin);

  const originOk = origin && (ALLOWED_ORIGINS.has(origin) || /^http:\/\/localhost(:\d+)?$/.test(origin));
  if (!originOk) return reply(403, { error: "Not allowed" }, origin);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return reply(400, { error: "Invalid request" }, origin);
  }

  // Hidden field that people never see; bots tend to fill it in.
  if (text(body.website, 200) !== "") return reply(200, { ok: true }, origin);

  const service = SERVICES[text(body.service, 100)];
  const timing = TIMINGS[text(body.timing, 100)] ?? "flexible";
  const name = text(body.name, 120);
  const zip = text(body.zip, 10);
  const phone = normalizePhone(text(body.phone, 30));
  const details = text(body.details, 2000);
  const consentText = text(body.consent_text, 2000);
  const source = text(body.source, 100) || null;

  const problems: string[] = [];
  if (!service) problems.push("service");
  if (name.length < 2) problems.push("name");
  if (!/^[0-9]{5}$/.test(zip)) problems.push("zip");
  if (!phone) problems.push("phone");
  if (consentText.length < 40 || body.consent !== true) problems.push("consent");
  if (problems.length) return reply(422, { error: "Please check these fields", fields: problems }, origin);

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

  // Find or create the homeowner by phone.
  const { data: existing, error: findError } = await db
    .from("homeowners").select("id").eq("phone", phone).order("created_at").limit(1);
  if (findError) return reply(500, { error: "Something went wrong. Please call us." }, origin);

  let homeownerId = existing?.[0]?.id as string | undefined;

  if (homeownerId) {
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const { count } = await db.from("requests").select("id", { count: "exact", head: true })
      .eq("homeowner_id", homeownerId).gte("created_at", since);
    if ((count ?? 0) >= MAX_REQUESTS_PER_PHONE_PER_DAY) {
      return reply(429, { error: "We already have your requests. A pro will be in touch." }, origin);
    }
    await db.from("homeowners").update({ name, zip }).eq("id", homeownerId);
  } else {
    const { data: created, error: createError } = await db
      .from("homeowners").insert({ name, phone, zip }).select("id").single();
    if (createError || !created) return reply(500, { error: "Something went wrong. Please call us." }, origin);
    homeownerId = created.id;
  }

  const ip = (req.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || null;

  const { data: request, error: requestError } = await db.from("requests").insert({
    homeowner_id: homeownerId,
    service,
    details: details || null,
    zip,
    timing,
    status: "new",
    source,
    consent_text: consentText,
    consent_ip: ip,
    consent_user_agent: text(req.headers.get("user-agent"), 500) || null,
  }).select("id").single();

  if (requestError || !request) return reply(500, { error: "Something went wrong. Please call us." }, origin);

  return reply(201, { ok: true, request_id: request.id }, origin);
});
