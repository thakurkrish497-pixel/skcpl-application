-- ============================================================================
-- SKCPL Official Announcements & Sitewise Notices Table Schema
-- Supports Company-Wide broadcasts, Sitewise notices, and Zoom meeting links.
-- Authorized creators: Admin, Project Head, Accounts.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.site_announcements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    category TEXT NOT NULL DEFAULT 'general', -- 'general', 'meeting', 'urgent', 'celebration'
    target_site_id TEXT,                     -- NULL or 'all' for company-wide broadcast
    target_site_name TEXT DEFAULT 'All Sites',
    meeting_link TEXT,                       -- Optional Zoom / Google Meet / Teams link
    scheduled_at TIMESTAMP WITH TIME ZONE,   -- Optional scheduled meeting or event time
    created_by_name TEXT NOT NULL,
    created_by_role TEXT NOT NULL,           -- 'Admin', 'Project Head', 'Accounts'
    created_by_id TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE
);

CREATE INDEX IF NOT EXISTS idx_site_announcements_target_site ON public.site_announcements(target_site_id);
CREATE INDEX IF NOT EXISTS idx_site_announcements_created_at ON public.site_announcements(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_site_announcements_is_active ON public.site_announcements(is_active);

-- Enable RLS and public read policies
ALTER TABLE public.site_announcements ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow public read access to announcements"
ON public.site_announcements
FOR SELECT
USING (true);

CREATE POLICY "Allow authenticated users to insert/update announcements"
ON public.site_announcements
FOR ALL
USING (true)
WITH CHECK (true);
