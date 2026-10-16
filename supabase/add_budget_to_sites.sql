-- Adds allocated_budget column to sites table for Cashflow Management

ALTER TABLE public.sites 
ADD COLUMN IF NOT EXISTS allocated_budget NUMERIC(14, 2) DEFAULT 0;

-- Optionally, you can set existing sites to 0 explicitly if needed, but DEFAULT 0 handles it.
