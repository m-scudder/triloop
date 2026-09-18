-- Supabase's database linter reported this pre-existing SECURITY DEFINER
-- function as executable through the Data API. TriLoop does not call it.
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
