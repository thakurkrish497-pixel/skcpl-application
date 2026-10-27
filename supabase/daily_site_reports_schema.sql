-- ========================================================
-- SKCPL Construction Management: Daily Site Reports Schema
-- ========================================================

CREATE TABLE IF NOT EXISTS public.daily_site_reports (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    site_id UUID NOT NULL REFERENCES public.sites(id) ON DELETE CASCADE,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    submitted_by TEXT,
    audio_url TEXT,
    photo_urls TEXT[] DEFAULT '{}'::TEXT[],
    notes TEXT,
    raw_transcript TEXT,
    work_done JSONB DEFAULT '[]'::JSONB,
    tomorrow_plan JSONB DEFAULT '[]'::JSONB,
    manpower_details TEXT,
    materials_used TEXT,
    remarks TEXT,
    ai_summary JSONB DEFAULT '{}'::JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Index for fast site & date lookups
CREATE INDEX IF NOT EXISTS idx_daily_site_reports_site_date 
ON public.daily_site_reports (site_id, date DESC);

-- Enable RLS
ALTER TABLE public.daily_site_reports ENABLE ROW LEVEL SECURITY;

-- Allow read access for authenticated users & anon
CREATE POLICY "Allow select daily_site_reports" 
ON public.daily_site_reports FOR SELECT 
USING (true);

-- Allow insert/update/delete
CREATE POLICY "Allow insert daily_site_reports" 
ON public.daily_site_reports FOR INSERT 
WITH CHECK (true);

CREATE POLICY "Allow update daily_site_reports" 
ON public.daily_site_reports FOR UPDATE 
USING (true);

CREATE POLICY "Allow delete daily_site_reports" 
ON public.daily_site_reports FOR DELETE 
USING (true);
