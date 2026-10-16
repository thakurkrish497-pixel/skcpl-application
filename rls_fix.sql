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

-- Fix Accounts RLS for reviewing/rejecting transactions
DROP POLICY IF EXISTS "Accounts reviews stock" ON public.stock_transactions;
CREATE POLICY "Accounts reviews stock"
  ON public.stock_transactions FOR UPDATE
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'accounts')
  );

DROP POLICY IF EXISTS "Accounts reviews cash" ON public.cash_transactions;
CREATE POLICY "Accounts reviews cash"
  ON public.cash_transactions FOR UPDATE
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'accounts')
  );
