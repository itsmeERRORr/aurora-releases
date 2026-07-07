// trial-sync: reconciles a device's free-trial counter.
//
// The client sends its local `used_actions` and its hashed device id. We store
// `max(existing, incoming)` atomically and return the authoritative value. The
// `greatest(...)` upsert means the count never goes down — deleting/editing the
// local file is corrected on the next call, while a forged low value from a
// tampered client can't lower the server's count.
//
// Uses the service-role key so it can write past RLS (which blocks anon writes).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "content-type": "application/json" },
    });
  }

  try {
    const { device_hash, used_actions } = await req.json();

    if (typeof device_hash !== "string" || device_hash.length < 16 || device_hash.length > 128) {
      return new Response(JSON.stringify({ error: "Invalid device_hash" }), {
        status: 400,
        headers: { ...corsHeaders, "content-type": "application/json" },
      });
    }

    // Clamp the incoming count to a sane range — never trust the client's number
    // beyond using it to raise the server's max.
    const incoming = Math.max(0, Math.min(Number(used_actions) || 0, 1_000_000));

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Single-statement atomic upsert (see trial_usage_bump in the migration):
    // raises the stored count to greatest(existing, incoming) and returns it.
    const { data, error } = await supabase.rpc("trial_usage_bump", {
      p_device_hash: device_hash,
      p_used: incoming,
    });

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { ...corsHeaders, "content-type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ used_actions: data }), {
      status: 200,
      headers: { ...corsHeaders, "content-type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 400,
      headers: { ...corsHeaders, "content-type": "application/json" },
    });
  }
});
