-- ==============================================================================
-- SMARTIFY MIGRATION 008: DROP DUPLICATE OVERLOADED ESCALATION FUNCTION
-- Description: Drops legacy 0-argument public.process_daily_complaint_escalations()
--              to resolve PostgREST PGRST203 function overload resolution ambiguity.
-- Invariant: The canonical escalation engine function accepts an optional p_limit
--            parameter with DEFAULT NULL. Having both signatures caused client
--            RPC discovery collisions. Dropping the legacy signature restores
--            deterministic RPC invocation across all client callers and automated jobs.
-- ==============================================================================

DROP FUNCTION IF EXISTS public.process_daily_complaint_escalations();
