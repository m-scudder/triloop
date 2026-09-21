import { withSupabase } from "npm:@supabase/server@1.7.0";

export default {
  fetch: withSupabase({ auth: "user" }, async (req: Request, ctx) => {
    if (req.method !== "DELETE") {
      return Response.json(
        { error: "Method not allowed" },
        { status: 405, headers: { Allow: "DELETE" } },
      );
    }

    const {
      data: { user },
      error: userError,
    } = await ctx.supabase.auth.getUser();

    if (userError || !user) {
      return Response.json({ error: "Authentication required" }, { status: 401 });
    }

    const { error: deleteError } = await ctx.supabaseAdmin.auth.admin.deleteUser(user.id);

    if (deleteError) {
      console.error("Account deletion failed", deleteError);
      return Response.json({ error: "Could not delete account" }, { status: 500 });
    }

    return Response.json({ deleted: true });
  }),
};
