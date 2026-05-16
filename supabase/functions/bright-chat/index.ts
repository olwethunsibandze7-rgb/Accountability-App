import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type BrightAction =
  | {
      type: "bright_change_habit_time";
      habit_id: string;
      habit_title: string;
      new_start_time: string;
      reason_category: string;
      reason: string;
      requires_confirmation: true;
    }
  | {
      type: "bright_change_habit_duration";
      habit_id: string;
      habit_title: string;
      new_duration_minutes: number;
      reason_category: string;
      reason: string;
      requires_confirmation: true;
    }
  | {
      type: "bright_add_goal_habits";
      goal_id: string;
      goal_title: string;
      habits: Array<Record<string, unknown>>;
      default_verifier_user_id: string | null;
      reason: string;
      requires_confirmation: true;
    };

type BrightResponse = {
  reply: string;
  action: BrightAction | null;
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function clampText(value: unknown, max = 700) {
  const text = String(value ?? "").trim();
  return text.length > max ? text.slice(0, max) : text;
}

function extractOutputText(openAiResponse: any): string {
  if (typeof openAiResponse?.output_text === "string") {
    return openAiResponse.output_text.trim();
  }

  const parts: string[] = [];

  for (const item of openAiResponse?.output ?? []) {
    for (const content of item?.content ?? []) {
      if (typeof content?.text === "string") {
        parts.push(content.text);
      }
    }
  }

  return parts.join("\n").trim();
}

function isValidTime(value: unknown): boolean {
  if (typeof value !== "string") return false;
  return /^([01]\d|2[0-3]):[0-5]\d$/.test(value.trim());
}

function isUuid(value: unknown): boolean {
  if (typeof value !== "string") return false;
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value.trim());
}

function normalizeAction(rawAction: unknown): BrightAction | null {
  if (!rawAction || typeof rawAction !== "object") return null;

  const action = rawAction as Record<string, unknown>;
  const type = String(action.type ?? "").trim();

  if (type === "bright_change_habit_time") {
    const habitId = String(action.habit_id ?? "").trim();
    const newStartTime = String(action.new_start_time ?? "").trim();

    if (!isUuid(habitId)) return null;
    if (!isValidTime(newStartTime)) return null;

    return {
      type: "bright_change_habit_time",
      habit_id: habitId,
      habit_title: clampText(action.habit_title, 120),
      new_start_time: newStartTime,
      reason_category: clampText(action.reason_category, 80),
      reason: clampText(action.reason, 500),
      requires_confirmation: true,
    };
  }

  if (type === "bright_change_habit_duration") {
    const habitId = String(action.habit_id ?? "").trim();
    const rawDuration = Number(action.new_duration_minutes);

    if (!isUuid(habitId)) return null;
    if (!Number.isFinite(rawDuration)) return null;

    const newDuration = Math.round(rawDuration);
    if (newDuration < 10 || newDuration > 180) return null;

    return {
      type: "bright_change_habit_duration",
      habit_id: habitId,
      habit_title: clampText(action.habit_title, 120),
      new_duration_minutes: newDuration,
      reason_category: clampText(action.reason_category, 80),
      reason: clampText(action.reason, 500),
      requires_confirmation: true,
    };
  }

  if (type === "bright_add_goal_habits") {
    const goalId = String(action.goal_id ?? "").trim();

    if (!isUuid(goalId)) return null;

    const habits = Array.isArray(action.habits)
      ? action.habits
          .filter((item) => item && typeof item === "object")
          .slice(0, 4)
          .map((item) => item as Record<string, unknown>)
      : [];

    if (habits.length === 0) return null;

    const verifierRaw = action.default_verifier_user_id;
    const verifierId =
      typeof verifierRaw === "string" && isUuid(verifierRaw)
        ? verifierRaw
        : null;

    return {
      type: "bright_add_goal_habits",
      goal_id: goalId,
      goal_title: clampText(action.goal_title, 120),
      habits,
      default_verifier_user_id: verifierId,
      reason: clampText(action.reason, 500),
      requires_confirmation: true,
    };
  }

  return null;
}

function safeParseBrightJson(raw: string): BrightResponse {
  try {
    const parsed = JSON.parse(raw);

    const reply = clampText(parsed.reply, 700);
    const action = normalizeAction(parsed.action);

    if (!reply) {
      return {
        reply:
          "I could not form a clean response. Ask again with the task, change, and real reason.",
        action: null,
      };
    }

    return {
      reply,
      action,
    };
  } catch {
    return {
      reply:
        "I could not parse that cleanly. Ask again with the task, change, and real reason.",
      action: null,
    };
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  try {
    const openAiKey = Deno.env.get("OPENAI_API_KEY");
    const model = Deno.env.get("BRIGHT_OPENAI_MODEL") ?? "gpt-4.1-mini";

    if (!openAiKey) {
      return jsonResponse({ error: "OPENAI_API_KEY is not configured." }, 500);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");

    if (!supabaseUrl || !supabaseAnonKey) {
      return jsonResponse(
        { error: "Supabase environment is not configured." },
        500,
      );
    }

    const authHeader = req.headers.get("Authorization");

    if (!authHeader) {
      return jsonResponse({ error: "Missing Authorization header." }, 401);
    }

    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: {
        headers: {
          Authorization: authHeader,
        },
      },
    });

    const {
      data: { user },
      error: userError,
    } = await supabase.auth.getUser();

    if (userError || !user) {
      return jsonResponse({ error: "Unauthorized." }, 401);
    }

    const body = await req.json().catch(() => null);

    const userMessage = clampText(body?.message, 600);
    const recentMessages = Array.isArray(body?.recent_messages)
      ? body.recent_messages.slice(-8)
      : [];

    if (!userMessage) {
      return jsonResponse({ error: "Message is required." }, 400);
    }

    const [goalsResult, habitsResult, friendsResult] = await Promise.all([
      supabase
        .from("goals")
        .select("goal_id, title, category, why, success_metric")
        .eq("active", true)
        .limit(8),

      supabase
        .from("habits")
        .select(
          `
          habit_id,
          goal_id,
          title,
          verification_type,
          evidence_type,
          duration_minutes,
          min_valid_minutes,
          min_completion_ratio,
          requires_verifier,
          preferred_time_of_day,
          preferred_days,
          schedule_reason,
          review_after_days,
          habit_schedules (
            schedule_id,
            day_of_week,
            start_time,
            end_time
          )
        `,
        )
        .eq("active", true)
        .limit(30),

      supabase
        .from("friendships")
        .select("friendship_id, requester_id, addressee_id, status")
        .eq("status", "accepted")
        .or(`requester_id.eq.${user.id},addressee_id.eq.${user.id}`)
        .limit(20),
    ]);

    if (goalsResult.error) {
      return jsonResponse({ error: goalsResult.error.message }, 500);
    }

    if (habitsResult.error) {
      return jsonResponse({ error: habitsResult.error.message }, 500);
    }

    if (friendsResult.error) {
      return jsonResponse({ error: friendsResult.error.message }, 500);
    }

    const compactContext = {
      user_id: user.id,
      goals: goalsResult.data ?? [],
      habits: habitsResult.data ?? [],
      friend_count: friendsResult.data?.length ?? 0,
      valid_schedule_reason_categories: [
        "class_schedule",
        "work_shift",
        "transport",
        "facility_hours",
        "verifier_availability",
        "recurring_conflict",
        "health_family",
        "fixed_commitment",
      ],
      valid_duration_reason_categories: [
        "progression",
        "consistency_proven",
        "goal_intensity",
        "training_progression",
        "academic_demand",
        "fixed_commitment",
      ],
      allowed_verification_types: [
        "focus_auto",
        "partner",
        "focus_partner",
        "location",
        "location_focus",
        "location_partner",
        "location_focus_partner",
      ],
      habit_creation_rules: {
        final_active_habits_per_goal_must_be: "3 or 4",
        manual_verification_allowed: false,
        review_after_days: 21,
        every_habit_requires_verification: true,
      },
      schedule_change_rules: {
        max_time_changes_per_habit_per_month: 1,
        future_logs_only: true,
        requires_confirmation: true,
      },
      duration_change_rules: {
        only_increase_duration: true,
        max_duration_changes_per_habit_per_month: 1,
        future_logs_only: true,
        requires_confirmation: true,
      },
    };

    const systemPrompt = `
You are Bright, the strict accountability operator inside Achievr.

Style:
- Keep replies under 90 words.
- Be direct, calm, and strict.
- No motivational fluff.
- Do not help users weaken accountability.
- Never claim a change was made. You only propose actions.
- Every app-changing action requires user confirmation.
- Do not ask the same question repeatedly if the user already gave enough information.

Core behavior:
- If details are missing, ask one short question.
- If details are enough, propose an action.
- If the reason is weak, reject it without an action.
- Do not suggest next tasks or explain penalties unless asked.

Very important distinction:
- "Move to 18:00", "change to 6 PM", "reschedule to 13:30" means bright_change_habit_time.
- "Increase to 70 minutes", "make it 40 minutes", "extend duration" means bright_change_habit_duration.
- Do not confuse time of day with duration.
- If user says "change time" but gives minutes, ask one clarifying question.

Schedule change rules:
- Needs a real constraint, not an excuse.
- Valid reason categories: class_schedule, work_shift, transport, facility_hours, verifier_availability, recurring_conflict, health_family, fixed_commitment.
- Reject lazy reasons, tiredness, forgetting, avoiding penalties, wanting easier points.
- Only one time change per habit per month.

Duration change rules:
- Bright can increase duration when discipline improves.
- Valid duration reason categories: progression, consistency_proven, goal_intensity, training_progression, academic_demand, fixed_commitment.
- Bright should not reduce duration through this action.
- Only one duration change per habit per month.
- If user asks to increase from X to Y minutes and gives a good reason, propose bright_change_habit_duration.

Habit creation rules:
- Habit creation must leave a goal with exactly 3 or 4 active habits.
- Every Bright-created habit needs a strong verification method.
- Study/coursework usually uses focus_partner.
- Gym/location tasks usually use location_focus_partner.
- Reading/flashcards may use focus_auto if lower risk.
- Partner-based habits require a verifier later if not provided.
- Place tasks strategically: workout morning or early evening; deep work earlier/evening; review in evening.

Output only valid JSON:
{
  "reply": "short message",
  "action": null
}

For changing task time:
{
  "reply": "short message",
  "action": {
    "type": "bright_change_habit_time",
    "habit_id": "uuid from context",
    "habit_title": "title from context",
    "new_start_time": "HH:MM",
    "reason_category": "one valid schedule category",
    "reason": "clear reason",
    "requires_confirmation": true
  }
}

For increasing task duration:
{
  "reply": "short message",
  "action": {
    "type": "bright_change_habit_duration",
    "habit_id": "uuid from context",
    "habit_title": "title from context",
    "new_duration_minutes": 70,
    "reason_category": "one valid duration category",
    "reason": "clear reason",
    "requires_confirmation": true
  }
}

For adding habits:
{
  "reply": "short message",
  "action": {
    "type": "bright_add_goal_habits",
    "goal_id": "uuid from context",
    "goal_title": "title from context",
    "habits": [
      {
        "title": "Habit title",
        "description": "short description",
        "habit_kind": "study|workout|review|admin|general",
        "verification_type": "focus_partner|location_focus_partner|partner|focus_auto|location_partner",
        "evidence_type": "focus_summary|focus_session|note|photo|focus_plus_note",
        "target_frequency": "daily|weekly",
        "duration_minutes": 30,
        "min_completion_ratio": 0.75,
        "start_time": "HH:MM",
        "preferred_days": [1,2,3,4,5]
      }
    ],
    "default_verifier_user_id": null,
    "reason": "why Bright created this structure",
    "requires_confirmation": true
  }
}
`;

    const inputPayload = {
      user_message: userMessage,
      recent_messages: recentMessages,
      app_context: compactContext,
    };

    const openAiResponse = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${openAiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
        input: [
          {
            role: "system",
            content: systemPrompt,
          },
          {
            role: "user",
            content: JSON.stringify(inputPayload),
          },
        ],
        max_output_tokens: 600,
      }),
    });

    if (!openAiResponse.ok) {
      const errorText = await openAiResponse.text();

      return jsonResponse(
        {
          error: "OpenAI request failed.",
          details: errorText,
        },
        500,
      );
    }

    const aiJson = await openAiResponse.json();
    const outputText = extractOutputText(aiJson);
    const brightResponse = safeParseBrightJson(outputText);

    return jsonResponse(brightResponse);
  } catch (e) {
    return jsonResponse(
      {
        error: e instanceof Error ? e.message : String(e),
      },
      500,
    );
  }
});