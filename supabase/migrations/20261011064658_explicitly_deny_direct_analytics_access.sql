create policy "No direct analytics event access"
on public.analytics_events
as restrictive
for all
to anon, authenticated
using (false)
with check (false);

create policy "No direct analytics admin access"
on public.analytics_admins
as restrictive
for all
to anon, authenticated
using (false)
with check (false);
