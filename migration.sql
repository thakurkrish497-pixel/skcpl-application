ALTER TABLE public.dropdowns ADD COLUMN IF NOT EXISTS site_id UUID REFERENCES public.sites(id) ON DELETE CASCADE;
ALTER TABLE public.stock_transactions ADD COLUMN IF NOT EXISTS photo_urls TEXT[] DEFAULT '{}';
ALTER TABLE public.stock_transactions ADD COLUMN IF NOT EXISTS unregistered_vendor TEXT;
ALTER TABLE public.cash_transactions ADD COLUMN IF NOT EXISTS photo_urls TEXT[] DEFAULT '{}';

-- Allow workers to submit without a UUID
ALTER TABLE public.stock_transactions ALTER COLUMN submitted_by DROP NOT NULL;
ALTER TABLE public.cash_transactions ALTER COLUMN submitted_by DROP NOT NULL;

-- Drop old constraints and update
ALTER TABLE public.dropdowns DROP CONSTRAINT IF EXISTS dropdowns_category_value_key;
ALTER TABLE public.dropdowns DROP CONSTRAINT IF EXISTS dropdowns_site_id_category_value_key;
ALTER TABLE public.dropdowns ADD CONSTRAINT dropdowns_site_id_category_value_key UNIQUE (site_id, category, value);

-- Create cash view
DROP VIEW IF EXISTS public.site_current_cash CASCADE;
CREATE VIEW public.site_current_cash AS
SELECT
  ct.site_id,
  s.name AS site_name,
  COALESCE(SUM(ct.amount_received), 0) AS total_inbound,
  COALESCE(SUM(ct.expense_amount), 0) AS total_outbound,
  COALESCE(SUM(ct.amount_received), 0) - COALESCE(SUM(ct.expense_amount), 0) AS current_cash
FROM public.cash_transactions ct
JOIN public.sites s ON s.id = ct.site_id
WHERE ct.status = 'approved'
GROUP BY ct.site_id, s.name;

-- Update RLS for Accounts
DROP POLICY IF EXISTS "Accounts reviews stock" ON public.stock_transactions;
CREATE POLICY "Accounts reviews stock"
  ON public.stock_transactions FOR UPDATE
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'accounts')
    AND status IN ('pending_accounts', 'pending_admin')
  );

DROP POLICY IF EXISTS "Accounts reviews cash" ON public.cash_transactions;
CREATE POLICY "Accounts reviews cash"
  ON public.cash_transactions FOR UPDATE
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'accounts')
    AND status IN ('pending_accounts', 'pending_admin')
  );

-- Create bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('transaction_photos', 'transaction_photos', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Authenticated users can upload photos" ON storage.objects;
CREATE POLICY "Authenticated users can upload photos"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'transaction_photos' AND
    auth.role() = 'authenticated'
  );

DROP POLICY IF EXISTS "Authenticated users can view photos" ON storage.objects;
CREATE POLICY "Authenticated users can view photos"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'transaction_photos' AND
    auth.role() = 'authenticated'
  );

DROP POLICY IF EXISTS "Authenticated users can update own photos" ON storage.objects;
CREATE POLICY "Authenticated users can update own photos"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'transaction_photos' AND
    auth.role() = 'authenticated'
  );
-- Fix Stock Transactions for Site Workers
DROP POLICY IF EXISTS "Worker inserts stock" ON public.stock_transactions;
CREATE POLICY "Worker inserts stock"
  ON public.stock_transactions FOR INSERT
  WITH CHECK (auth.role() = 'anon' OR auth.uid() = submitted_by);

DROP POLICY IF EXISTS "Worker views own stock" ON public.stock_transactions;
CREATE POLICY "Worker views own stock"
  ON public.stock_transactions FOR SELECT
  USING (auth.role() = 'anon' OR auth.uid() = submitted_by);

DROP POLICY IF EXISTS "Worker edits pending stock" ON public.stock_transactions;
CREATE POLICY "Worker edits pending stock"
  ON public.stock_transactions FOR UPDATE
  USING ((auth.role() = 'anon' OR auth.uid() = submitted_by) AND status = 'pending_accounts');

-- Fix Cash Transactions for Site Workers
DROP POLICY IF EXISTS "Worker inserts cash" ON public.cash_transactions;
CREATE POLICY "Worker inserts cash"
  ON public.cash_transactions FOR INSERT
  WITH CHECK (auth.role() = 'anon' OR auth.uid() = submitted_by);

DROP POLICY IF EXISTS "Worker views own cash" ON public.cash_transactions;
CREATE POLICY "Worker views own cash"
  ON public.cash_transactions FOR SELECT
  USING (auth.role() = 'anon' OR auth.uid() = submitted_by);

DROP POLICY IF EXISTS "Worker edits pending cash" ON public.cash_transactions;
CREATE POLICY "Worker edits pending cash"
  ON public.cash_transactions FOR UPDATE
  USING ((auth.role() = 'anon' OR auth.uid() = submitted_by) AND status = 'pending_accounts');
