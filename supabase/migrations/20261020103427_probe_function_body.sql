-- Recorded on the project while it was being set up (2026-10-20): a check that function bodies containing
-- UPDATE are accepted by the migration tool. The function is never called and has no privileges; it is
-- dropped together with the other setup leftovers (see docs/backend/README.md, "片付け").
CREATE FUNCTION public._probe() RETURNS void LANGUAGE plpgsql SET search_path = '' AS $$ BEGIN UPDATE public.nothing SET x = 1; END $$;
REVOKE ALL ON FUNCTION public._probe() FROM PUBLIC, anon, authenticated, service_role;
