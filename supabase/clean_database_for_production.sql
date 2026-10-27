-- ============================================================
-- SKCPL ERP — Production Database Cleanup Script
-- Run this in the Supabase SQL Editor to wipe all test data
-- ============================================================

BEGIN;

-- 1. Wipe all test transactional records
TRUNCATE TABLE public.cash_transactions CASCADE;
TRUNCATE TABLE public.stock_transactions CASCADE;

-- If attendance and DSR tables exist in your Supabase schema:
DO $$
BEGIN
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'attendance') THEN
    TRUNCATE TABLE public.attendance CASCADE;
  END IF;
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'attendance_regularization') THEN
    TRUNCATE TABLE public.attendance_regularization CASCADE;
  END IF;
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'daily_site_reports') THEN
    TRUNCATE TABLE public.daily_site_reports CASCADE;
  END IF;
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'site_announcements') THEN
    TRUNCATE TABLE public.site_announcements CASCADE;
  END IF;
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'tasks') THEN
    TRUNCATE TABLE public.tasks CASCADE;
  END IF;
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'task_comments') THEN
    TRUNCATE TABLE public.task_comments CASCADE;
  END IF;
  IF EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'site_staff') THEN
    TRUNCATE TABLE public.site_staff CASCADE;
  END IF;
END $$;

-- 2. Wipe all test dropdowns and sites completely
TRUNCATE TABLE public.dropdowns CASCADE;
TRUNCATE TABLE public.sites CASCADE;

-- 3. Preserve Admin account and clear any other test users in public.users
DELETE FROM public.users WHERE email NOT IN ('admin@skcpl.com', 'admin@skumarcreation.com');

COMMIT;

-- Verification query
SELECT 
  (SELECT COUNT(*) FROM public.sites) AS remaining_sites,
  (SELECT COUNT(*) FROM public.dropdowns) AS remaining_dropdowns,
  (SELECT COUNT(*) FROM public.cash_transactions) AS remaining_cash_tx,
  (SELECT COUNT(*) FROM public.stock_transactions) AS remaining_stock_tx,
  (SELECT COUNT(*) FROM public.users) AS remaining_users;
