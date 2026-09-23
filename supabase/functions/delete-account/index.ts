import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  if (req.method !== "DELETE") {
    return Response.json(
      { error: "Method not allowed" },
      { status: 405, headers: { Allow: "DELETE" } },
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authorization = req.headers.get("Authorization");

  if (!supabaseUrl || !anonKey || !serviceRoleKey || !authorization) {
    return Response.json({ error: "Server configuration is incomplete" }, { status: 500 });
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: {
      headers: { Authorization: authorization },
    },
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });

  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser();

  if (userError || !user) {
    return Response.json({ error: "Authentication required" }, { status: 401 });
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
    },
  });

  const { error: deleteError } = await adminClient.auth.admin.deleteUser(user.id);

  if (deleteError) {
    console.error("Account deletion failed", deleteError);
    return Response.json(
      { error: "Could not delete account", detail: deleteError.message },
      { status: 500 },
    );
  }

  // Do not report success until Auth confirms the record is actually gone.
  const { data: remainingUser, error: verifyError } =
    await adminClient.auth.admin.getUserById(user.id);

  if (!verifyError && remainingUser?.user) {
    console.error("Account deletion verification failed", { userID: user.id });
    return Response.json(
      { error: "Account still exists after deletion attempt" },
      { status: 500 },
    );
  }

  return Response.json({ deleted: true });
});
