-- ========================================================
-- SKCPL Construction Management: Site Staff & Hierarchy Schema
-- ========================================================

CREATE TABLE IF NOT EXISTS public.site_staff (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    site_id UUID NOT NULL REFERENCES public.sites(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('worker', 'supervisor')),
    pin TEXT NOT NULL DEFAULT '1234',
    description TEXT,
    date_of_birth TIMESTAMP WITH TIME ZONE,
    aadhar_number TEXT,
    aadhar_card_url TEXT,
    pan_number TEXT,
    pan_card_url TEXT,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Indexes for lightning fast lookups by site and active status
CREATE INDEX IF NOT EXISTS idx_site_staff_site_id ON public.site_staff(site_id);
CREATE INDEX IF NOT EXISTS idx_site_staff_role ON public.site_staff(role);

-- Enable Row Level Security
ALTER TABLE public.site_staff ENABLE ROW LEVEL SECURITY;

-- Allow full access for anon & service role
CREATE POLICY "Allow select site_staff" ON public.site_staff FOR SELECT USING (true);
CREATE POLICY "Allow insert site_staff" ON public.site_staff FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow update site_staff" ON public.site_staff FOR UPDATE USING (true);
CREATE POLICY "Allow delete site_staff" ON public.site_staff FOR DELETE USING (true);
