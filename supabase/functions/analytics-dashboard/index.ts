import { createClient } from "npm:@supabase/supabase-js@2.95.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://m-scudder.github.io",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-athevia-admin-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function bytesToHex(bytes: Uint8Array) {
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function sha256Hex(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return bytesToHex(new Uint8Array(digest));
}

function rangeStart(range: string) {
  const ms: Record<string, number> = {
    "24h": 24 * 60 * 60 * 1000,
    "7d": 7 * 24 * 60 * 60 * 1000,
    "30d": 30 * 24 * 60 * 60 * 1000,
    "90d": 90 * 24 * 60 * 60 * 1000,
  };
  return new Date(Date.now() - (ms[range] ?? ms["7d"]));
}

function isUUID(value: unknown): value is string {
  return typeof value === "string"
    && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function isTrainingWorkout(workout: any) {
  return ["running", "cycling", "swimming", "multisport"].includes(String(workout?.discipline));
}

function dateInRange(value: unknown, start: Date, end = new Date()) {
  if (typeof value !== "string") return false;
  const date = new Date(value);
  return !Number.isNaN(date.getTime()) && date >= start && date <= end;
}

function latestSnapshots(rows: any[]) {
  const map = new Map<string, any>();
  for (const row of rows ?? []) {
    if (!map.has(row.user_id)) map.set(row.user_id, row);
  }
  return map;
}

function unique<T>(values: T[]) {
  return [...new Set(values)];
}

function compactContext(properties: Record<string, unknown> | null | undefined) {
  if (!properties) return "";
  return Object.entries(properties)
    .filter(([, value]) => typeof value === "string" && value.length)
    .slice(0, 4)
    .map(([key, value]) => `${key}: ${value}`)
    .join(" · ");
}

function eventOutcome(name: string) {
  if (name.endsWith("_failed")) return "fail";
  if (name.endsWith("_succeeded") || ["workout_completed", "onboarding_completed", "workout_matched"].includes(name)) return "success";
  return "info";
}

function decodeBase64JSON(value: unknown): any {
  if (typeof value !== "string" || !value.length) return null;
  try {
    const decoded = Uint8Array.from(atob(value), (char) => char.charCodeAt(0));
    return JSON.parse(new TextDecoder().decode(decoded));
  } catch {
    return null;
  }
}

function setupDetail(athlete: any) {
  const setup = athlete?.setup;
  if (!setup) return null;
  const objective = decodeBase64JSON(setup.objectiveData)
    ?? (setup.goal ? { kind: setup.goal } : null);
  const openWater = decodeBase64JSON(setup.openWaterConsentData);
  const eventState = decodeBase64JSON(setup.eventStateData);
  const trainingDayTarget = decodeBase64JSON(setup.trainingDayTargetData) ?? 3;

  return {
    stage: setup.stage ?? null,
    completedAt: setup.completedAt ?? null,
    objective,
    legacyGoal: setup.goal ?? null,
    baseline: setup.baseline ?? null,
    birthDate: setup.birthDate ?? null,
    planStartDate: setup.planStartDate ?? null,
    schedule: setup.schedule ?? null,
    sportPreferences: Array.isArray(setup.preferences) ? setup.preferences : [],
    trainingDayTarget,
    openWaterTrainingConsent: openWater,
    eventState,
  };
}

function progressDetail(plans: any[]) {
  const ordered = [...plans].sort((a: any, b: any) => String(a.startDate ?? "").localeCompare(String(b.startDate ?? "")));
  const recent = ordered.slice(-4);
  const training = recent.flatMap((plan: any) => (plan.workouts ?? []).filter(isTrainingWorkout));
  const completed = training.filter((workout: any) => workout.status === "completed");
  const now = new Date();
  const due = training.filter((workout: any) => {
    const date = new Date(workout.date);
    return !Number.isNaN(date.getTime()) && date <= now;
  });
  const trainingSeconds = completed.reduce((total: number, workout: any) =>
    total + Number(workout.recorded?.durationSeconds ?? workout.prescribedDurationSeconds ?? 0), 0);

  const bySport: Record<string, any> = {};
  for (const workout of completed) {
    const sport = String(workout.discipline ?? "other");
    const current = bySport[sport] ?? {
      sport,
      completedWorkouts: 0,
      recordedDurationSeconds: 0,
      recordedDistanceMeters: 0,
      bestDistanceMeters: null,
      latestCompletedAt: null,
    };
    current.completedWorkouts += 1;
    current.recordedDurationSeconds += Number(workout.recorded?.durationSeconds ?? workout.prescribedDurationSeconds ?? 0);
    if (workout.recorded?.distanceMeters != null) {
      const distance = Number(workout.recorded.distanceMeters);
      current.recordedDistanceMeters += distance;
      current.bestDistanceMeters = current.bestDistanceMeters == null
        ? distance : Math.max(current.bestDistanceMeters, distance);
    }
    const completedAt = workout.completedAt ?? workout.recorded?.endDate ?? workout.date ?? null;
    if (completedAt && (!current.latestCompletedAt || String(completedAt) > String(current.latestCompletedAt))) {
      current.latestCompletedAt = completedAt;
    }
    bySport[sport] = current;
  }

  const allTraining = ordered.flatMap((plan: any) => (plan.workouts ?? []).filter(isTrainingWorkout));
  const allCompleted = allTraining.filter((workout: any) => workout.status === "completed");
  return {
    lastFourWeeks: {
      trainingSeconds,
      completedWorkouts: completed.length,
      dueWorkouts: due.length,
      adherencePercentage: due.length ? Math.round((due.filter((workout: any) => workout.status === "completed").length / due.length) * 100) : null,
    },
    lifetime: {
      planWeeks: ordered.length,
      completedPlanWeeks: ordered.filter((plan: any) => plan.status === "completed").length,
      completedWorkouts: allCompleted.length,
      totalRecordedDistanceMeters: allCompleted.reduce((total: number, workout: any) => total + Number(workout.recorded?.distanceMeters ?? 0), 0),
      totalRecordedDurationSeconds: allCompleted.reduce((total: number, workout: any) => total + Number(workout.recorded?.durationSeconds ?? workout.prescribedDurationSeconds ?? 0), 0),
    },
    sports: Object.values(bySport),
  };
}

function sanitizeStep(step: any): any {
  return {
    order: step?.order ?? 0,
    kind: step?.kind ?? null,
    title: step?.title ?? "",
    instructions: step?.instructions ?? null,
    durationSeconds: step?.durationSeconds ?? null,
    distanceMeters: step?.distanceMeters ?? null,
    targetIntensity: step?.targetIntensity ?? null,
    repeatCount: step?.repeatCount ?? null,
    children: Array.isArray(step?.children) ? step.children.map(sanitizeStep) : [],
  };
}

function sanitizeWorkout(workout: any) {
  const imported = workout?.importedSummary;
  const feedback = workout?.feedback;
  const recovery = workout?.recoveryCheckIn;

  return {
    id: workout?.id,
    date: workout?.date,
    discipline: workout?.discipline,
    title: workout?.title,
    goal: workout?.goal,
    targetRPE: workout?.targetRPE ?? null,
    prescribedDurationSeconds: workout?.prescribedDurationSeconds ?? null,
    targetDistanceMeters: workout?.targetDistanceMeters ?? null,
    status: workout?.status,
    completedAt: workout?.completedAt ?? null,
    origin: workout?.origin,
    steps: Array.isArray(workout?.steps) ? workout.steps.map(sanitizeStep) : [],
    feedback: feedback ? {
      rpe: feedback.rpe ?? null,
      painScore: feedback.painScore ?? null,
      painLocations: Array.isArray(feedback.painLocations) ? feedback.painLocations : [],
      recoveryFeeling: feedback.recoveryFeeling ?? null,
      symptoms: Array.isArray(feedback.symptoms) ? feedback.symptoms : [],
      createdAt: feedback.createdAt ?? null,
      // Free-form notes are intentionally absent from BackupSnapshot today.
      notesAvailable: false,
    } : null,
    recoveryCheckIn: recovery ? {
      date: recovery.date ?? null,
      painScore: recovery.painScore ?? null,
      soreness: recovery.soreness ?? null,
      energy: recovery.energy ?? null,
      symptoms: Array.isArray(recovery.symptoms) ? recovery.symptoms : [],
      createdAt: recovery.createdAt ?? null,
    } : null,
    recorded: imported ? {
      sport: imported.sport ?? null,
      startDate: imported.startDate ?? null,
      endDate: imported.endDate ?? null,
      durationSeconds: imported.duration ?? null,
      distanceMeters: imported.distanceMeters ?? null,
      averageHeartRate: imported.averageHeartRate ?? null,
      maximumHeartRate: imported.maximumHeartRate ?? null,
      elevationAscendedMeters: imported.elevationAscendedMeters ?? null,
      swimmingLengths: imported.swimmingLengths ?? null,
      swimmingStrokeCount: imported.swimmingStrokeCount ?? null,
      longestContinuousSwimMeters: imported.longestContinuousSwimMeters ?? null,
      metrics: imported.metrics ?? null,
      source: imported.source ?? null,
      importedAt: imported.importedAt ?? null,
    } : null,
  };
}

function sanitizePlan(plan: any) {
  const workouts = Array.isArray(plan?.workouts) ? plan.workouts.map(sanitizeWorkout) : [];
  const training = workouts.filter(isTrainingWorkout);
  const completed = training.filter((w: any) => w.status === "completed").length;
  const skipped = training.filter((w: any) => w.status === "skipped").length;
  return {
    id: plan?.id,
    weekNumber: plan?.weekNumber,
    startDate: plan?.startDate,
    endDate: plan?.endDate,
    status: plan?.status,
    generatedAt: plan?.generatedAt,
    generationReason: plan?.generationReason,
    generationReasonCode: plan?.generationReasonCode ?? null,
    parameters: plan?.parameters ?? null,
    completion: {
      planned: training.length,
      completed,
      skipped,
      percentage: training.length ? Math.round((completed / training.length) * 100) : 0,
    },
    workouts,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const token = req.headers.get("x-athevia-admin-token")?.trim();
  if (!token || token.length < 32 || token.length > 256) {
    return json(401, { error: "admin_session_required" });
  }

  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!url || !serviceRole) return json(500, { error: "server_not_configured" });

  const admin = createClient(url, serviceRole, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const tokenHash = await sha256Hex(token);
  const nowForSession = new Date();
  const { data: session, error: sessionError } = await admin
    .from("analytics_admin_sessions")
    .select("user_id,expires_at")
    .eq("token_hash", tokenHash)
    .maybeSingle();

  if (sessionError) return json(500, { error: "admin_session_check_failed" });
  if (!session || new Date(session.expires_at) <= nowForSession) {
    if (session) {
      await admin.from("analytics_admin_sessions").delete().eq("token_hash", tokenHash);
    }
    return json(401, { error: "admin_session_expired" });
  }

  const { data: adminRow, error: adminError } = await admin
    .from("analytics_admins")
    .select("user_id")
    .eq("user_id", session.user_id)
    .maybeSingle();

  if (adminError) return json(500, { error: "admin_check_failed" });
  if (!adminRow) return json(403, { error: "analytics_admin_required" });

  await admin
    .from("analytics_admin_sessions")
    .update({ last_used_at: nowForSession.toISOString() })
    .eq("token_hash", tokenHash);

  let body: any = {};
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const action = body?.action === "user_detail" ? "user_detail" : "overview";
  const environment = ["development", "testflight", "production"].includes(body?.environment)
    ? body.environment : "production";
  const range = ["24h", "7d", "30d", "90d"].includes(body?.range) ? body.range : "7d";
  const start = rangeStart(range);
  const now = new Date();

  if (action === "user_detail") {
    if (!isUUID(body?.user_id)) return json(400, { error: "invalid_user_id" });

    const [{ data: revisions, error: revisionsError }, { data: profile, error: profileError }, authResult] = await Promise.all([
      admin
        .from("backup_revisions")
        .select("created_at,snapshot")
        .eq("user_id", body.user_id)
        .order("created_at", { ascending: false })
        .limit(10),
      admin
        .from("account_profiles")
        .select("display_name,updated_at")
        .eq("user_id", body.user_id)
        .maybeSingle(),
      admin.auth.admin.getUserById(body.user_id),
    ]);

    if (revisionsError || profileError || authResult.error) {
      return json(500, { error: "user_detail_failed" });
    }

    const latest = revisions?.[0];
    if (!latest) return json(404, { error: "backup_not_found" });

    const snapshot: any = latest.snapshot ?? {};
    const plans = Array.isArray(snapshot.plans)
      ? snapshot.plans.map(sanitizePlan).sort((a: any, b: any) => (a.startDate ?? "").localeCompare(b.startDate ?? ""))
      : [];

    const athlete = snapshot.profile ?? {};
    const onboarding = setupDetail(athlete);
    return json(200, {
      user: {
        id: body.user_id,
        name: profile?.display_name ?? athlete.name ?? "Athlete",
        email: authResult.data.user?.email ?? null,
        lastBackupAt: latest.created_at,
        revisionCount: revisions?.length ?? 0,
      },
      profile: {
        experienceLevel: athlete.experienceLevel ?? null,
        trainingStartDate: athlete.trainingStartDate ?? null,
        poolLengthMeters: athlete.poolLengthMeters ?? null,
        usesMetricUnits: athlete.usesMetricUnits ?? true,
      },
      onboarding,
      preferences: onboarding ? {
        trainingDayTarget: onboarding.trainingDayTarget,
        schedule: onboarding.schedule,
        sportPreferences: onboarding.sportPreferences,
        openWaterTrainingConsent: onboarding.openWaterTrainingConsent,
        usesMetricUnits: athlete.usesMetricUnits ?? true,
        poolLengthMeters: athlete.poolLengthMeters ?? null,
      } : null,
      progress: progressDetail(plans),
      snapshotCreatedAt: snapshot.createdAt ?? latest.created_at,
      plans,
    });
  }

  const [
    revisionsResult,
    profilesResult,
    eventsResult,
    authUsersResult,
  ] = await Promise.all([
    admin
      .from("backup_revisions")
      .select("user_id,created_at,snapshot")
      .order("created_at", { ascending: false })
      .limit(1000),
    admin
      .from("account_profiles")
      .select("user_id,display_name,updated_at"),
    admin
      .from("analytics_events")
      .select("id,user_id,session_id,occurred_at,name,properties,app_version,app_build,environment")
      .eq("environment", environment)
      .gte("occurred_at", start.toISOString())
      .order("occurred_at", { ascending: false })
      .limit(5000),
    admin.auth.admin.listUsers({ page: 1, perPage: 1000 }),
  ]);

  if (revisionsResult.error || profilesResult.error || eventsResult.error || authUsersResult.error) {
    console.error("analytics-dashboard overview failed");
    return json(500, { error: "overview_failed" });
  }

  const revisions = revisionsResult.data ?? [];
  const latest = latestSnapshots(revisions);
  const profiles = new Map((profilesResult.data ?? []).map((row: any) => [row.user_id, row]));
  const authUsers = authUsersResult.data.users ?? [];
  const authById = new Map(authUsers.map((user: any) => [user.id, user]));
  const events = eventsResult.data ?? [];

  const allUserIds = unique([
    ...authUsers.map((user: any) => user.id),
    ...[...latest.keys()],
  ]);

  const eventsByUser = new Map<string, any[]>();
  for (const event of events) {
    const list = eventsByUser.get(event.user_id) ?? [];
    list.push(event);
    eventsByUser.set(event.user_id, list);
  }

  const allCurrentWorkouts: Array<any & { user_id: string }> = [];
  for (const [userId, revision] of latest.entries()) {
    const plans = Array.isArray(revision.snapshot?.plans) ? revision.snapshot.plans : [];
    for (const plan of plans) {
      for (const workout of Array.isArray(plan?.workouts) ? plan.workouts : []) {
        if (isTrainingWorkout(workout)) allCurrentWorkouts.push({ ...workout, user_id: userId });
      }
    }
  }

  const dueWorkouts = allCurrentWorkouts.filter((workout) => dateInRange(workout.date, start, now));
  const completedInRange = allCurrentWorkouts.filter((workout) =>
    workout.status === "completed" && dateInRange(workout.completedAt ?? workout.date, start, now)
  );

  const activeUsers = unique([
    ...events.map((event: any) => event.user_id),
    ...revisions.filter((row: any) => new Date(row.created_at) >= start).map((row: any) => row.user_id),
  ]).length;

  const sessions = unique(events.map((event: any) => event.session_id)).length;
  const completionRate = dueWorkouts.length
    ? Math.round((dueWorkouts.filter((w) => w.status === "completed").length / dueWorkouts.length) * 100)
    : 0;

  const dayCount = range === "24h" ? 1 : range === "7d" ? 7 : range === "30d" ? 30 : 90;
  const activitySeries = [];
  for (let offset = Math.min(dayCount, 30) - 1; offset >= 0; offset--) {
    const dayStart = new Date(now);
    dayStart.setUTCHours(0, 0, 0, 0);
    dayStart.setUTCDate(dayStart.getUTCDate() - offset);
    const dayEnd = new Date(dayStart.getTime() + 24 * 60 * 60 * 1000);
    const ids = unique([
      ...events.filter((e: any) => {
        const d = new Date(e.occurred_at);
        return d >= dayStart && d < dayEnd;
      }).map((e: any) => e.user_id),
      ...revisions.filter((r: any) => {
        const d = new Date(r.created_at);
        return d >= dayStart && d < dayEnd;
      }).map((r: any) => r.user_id),
    ]);
    activitySeries.push(ids.length);
  }

  const users = allUserIds.map((userId) => {
    const revision = latest.get(userId);
    const snapshot = revision?.snapshot ?? {};
    const userEvents = eventsByUser.get(userId) ?? [];
    const currentWorkouts: any[] = [];
    for (const plan of Array.isArray(snapshot.plans) ? snapshot.plans : []) {
      for (const workout of Array.isArray(plan?.workouts) ? plan.workouts : []) {
        if (isTrainingWorkout(workout)) currentWorkouts.push(workout);
      }
    }
    const completed = currentWorkouts.filter((w) =>
      w.status === "completed" && dateInRange(w.completedAt ?? w.date, start, now)
    ).length;
    const lastEvent = userEvents[0]?.occurred_at;
    const lastBackup = revision?.created_at;
    const lastSeen = [lastEvent, lastBackup].filter(Boolean).sort().reverse()[0] ?? null;
    const profile = profiles.get(userId);
    const authUser: any = authById.get(userId);
    return {
      id: userId,
      user: profile?.display_name ?? snapshot.profile?.name ?? "Athlete",
      email: authUser?.email ?? null,
      lastSeen,
      sessions: unique(userEvents.map((e: any) => e.session_id)).length,
      workouts: completed,
      planWeeks: Array.isArray(snapshot.plans) ? snapshot.plans.length : 0,
      completionRate: currentWorkouts.length
        ? Math.round((currentWorkouts.filter((w) => w.status === "completed").length / currentWorkouts.length) * 100)
        : 0,
      status: lastSeen && (now.getTime() - new Date(lastSeen).getTime()) < 7 * 24 * 60 * 60 * 1000 ? "Active" : "At risk",
    };
  }).sort((a, b) => String(b.lastSeen ?? "").localeCompare(String(a.lastSeen ?? "")));

  const sportCounts = new Map<string, number>();
  for (const workout of completedInRange) {
    const label = workout.discipline === "running" ? "Running"
      : workout.discipline === "cycling" ? "Cycling"
      : workout.discipline === "swimming" ? "Swimming" : "Multisport";
    sportCounts.set(label, (sportCounts.get(label) ?? 0) + 1);
  }
  const totalSports = [...sportCounts.values()].reduce((a, b) => a + b, 0);
  const sportColors: Record<string, string> = {
    Running: "#F7B538",
    Cycling: "#29C76B",
    Swimming: "#218CFF",
    Multisport: "#9E6BF2",
  };
  const sports = [...sportCounts.entries()].map(([label, count]) => ({
    label,
    value: totalSports ? Math.round((count / totalSports) * 100) : 0,
    color: sportColors[label] ?? "#8e8e93",
  }));

  const usersWithProfile = users.filter((u) => latest.get(u.id)?.snapshot?.profile).length;
  const usersWithPlan = users.filter((u) => (latest.get(u.id)?.snapshot?.plans?.length ?? 0) > 0).length;
  const usersWithCompletion = users.filter((u) => {
    const plans = latest.get(u.id)?.snapshot?.plans ?? [];
    return plans.some((p: any) => (p.workouts ?? []).some((w: any) => isTrainingWorkout(w) && w.status === "completed"));
  }).length;
  const usersWithCompletedWeek = users.filter((u) => {
    const plans = latest.get(u.id)?.snapshot?.plans ?? [];
    return plans.some((p: any) => p.status === "completed");
  }).length;
  const base = Math.max(users.length, 1);
  const onboarding = [
    ["Account", Math.round((users.length / base) * 100)],
    ["Profile", Math.round((usersWithProfile / base) * 100)],
    ["Plan generated", Math.round((usersWithPlan / base) * 100)],
    ["First workout", Math.round((usersWithCompletion / base) * 100)],
    ["Week completed", Math.round((usersWithCompletedWeek / base) * 100)],
  ];

  const uniqueUsersFor = (names: string[]) =>
    unique(events.filter((e: any) => names.includes(e.name)).map((e: any) => e.user_id)).length;

  const journey = [
    { stage: "Plan generated", users: usersWithPlan, conversion: Math.round((usersWithPlan / base) * 100) },
    { stage: "Workout viewed", users: uniqueUsersFor(["workout_viewed", "$screen"]), conversion: Math.round((uniqueUsersFor(["workout_viewed", "$screen"]) / base) * 100) },
    { stage: "Workout started", users: uniqueUsersFor(["workout_started", "start_workout_succeeded"]), conversion: Math.round((uniqueUsersFor(["workout_started", "start_workout_succeeded"]) / base) * 100) },
    { stage: "Workout completed", users: usersWithCompletion, conversion: Math.round((usersWithCompletion / base) * 100) },
    { stage: "Feedback submitted", users: users.filter((u) => {
      const plans = latest.get(u.id)?.snapshot?.plans ?? [];
      return plans.some((p: any) => (p.workouts ?? []).some((w: any) => Boolean(w.feedback)));
    }).length, conversion: 0 },
    { stage: "Next week generated", users: users.filter((u) => (latest.get(u.id)?.snapshot?.plans?.length ?? 0) > 1).length, conversion: 0 },
  ];
  journey.forEach((item) => item.conversion = Math.round((item.users / base) * 100));

  const planReasons = new Map<string, number>();
  for (const event of events.filter((e: any) => e.name === "plan_regenerated")) {
    const reason = String(event.properties?.reason ?? "profile_changed");
    planReasons.set(reason, (planReasons.get(reason) ?? 0) + 1);
  }
  const planChanges = [...planReasons.entries()]
    .sort((a, b) => b[1] - a[1])
    .map(([reason, count]) => ({ reason, count, before: "Previous prescription", after: "Updated prescription" }));

  const watchNames = [
    ["Requested", "send_to_watch_requested"],
    ["Scheduled", "send_to_watch_succeeded"],
    ["Started", "start_workout_succeeded"],
    ["Completed", "workout_completed"],
    ["Synced", "healthkit_import_completed"],
    ["Matched", "workout_matched"],
  ];
  const watchBase = Math.max(uniqueUsersFor([watchNames[0][1]]), 1);
  const watch = watchNames.map(([stage, name]) => ({
    stage,
    value: Math.round((uniqueUsersFor([name]) / watchBase) * 100),
  }));

  const importNames = [
    ["Import started", "healthkit_import_started"],
    ["Workouts found", "import_workouts_succeeded"],
    ["Imported", "healthkit_import_completed"],
    ["Matched to plan", "workout_matched"],
  ];
  const importBase = Math.max(uniqueUsersFor([importNames[0][1]]), 1);
  const imports = importNames.map(([stage, name]) => ({
    stage,
    value: Math.round((uniqueUsersFor([name]) / importBase) * 100),
  }));

  const eventRows = events.slice(0, 200).map((event: any) => ({
    time: event.occurred_at,
    event: event.name,
    user: profiles.get(event.user_id)?.display_name ?? authById.get(event.user_id)?.email ?? "Athlete",
    email: authById.get(event.user_id)?.email ?? null,
    context: compactContext(event.properties),
    outcome: eventOutcome(event.name),
  }));

  const recentActivity = eventRows.slice(0, 10).map((event: any) => ({
    icon: event.outcome === "success" ? "✓" : event.outcome === "fail" ? "!" : "·",
    title: event.event.replaceAll("_", " "),
    detail: [event.user, event.context].filter(Boolean).join(" · "),
    time: event.time,
  }));

  return json(200, {
    summary: {
      activeUsers,
      sessions,
      workoutsCompleted: completedInRange.length,
      completionRate,
      activeUsersTrend: "Current period",
      sessionsTrend: "Current period",
      workoutsTrend: "Current period",
      completionTrend: "Scheduled workouts due in period",
    },
    activitySeries,
    onboarding,
    sports,
    recentActivity,
    users,
    journey,
    planChanges,
    watch,
    imports,
    events: eventRows,
  });
});
