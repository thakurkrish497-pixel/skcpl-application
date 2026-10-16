-- ============================================================
-- SKCPL Construction Management App — Database Schema
-- Target: Supabase (PostgreSQL)
-- ============================================================

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================
-- ENUMS
-- ============================================================

DROP TYPE IF EXISTS user_role CASCADE;
CREATE TYPE user_role AS ENUM ('admin', 'accounts', 'worker');

DROP TYPE IF EXISTS transaction_status CASCADE;
CREATE TYPE transaction_status AS ENUM (
  'pending_accounts',
  'pending_admin',
  'approved',
  'rejected'
);

DROP TYPE IF EXISTS transaction_type CASCADE;
CREATE TYPE transaction_type AS ENUM ('inbound', 'outbound');

DROP TYPE IF EXISTS dropdown_category CASCADE;
CREATE TYPE dropdown_category AS ENUM (
  'vendor',
  'product',
  'metric_unit',
  'expense_type'
);

-- ============================================================
-- USERS TABLE
-- Links to Supabase Auth (auth.users)
-- ============================================================

DROP TABLE IF EXISTS public.users CASCADE;
CREATE TABLE public.users (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email       TEXT UNIQUE NOT NULL,
  full_name   TEXT,
  role        user_role NOT NULL DEFAULT 'worker',
  is_active   BOOLEAN DEFAULT TRUE,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- SITES TABLE
-- Each construction site has unique login credentials for workers
-- ============================================================

DROP TABLE IF EXISTS public.sites CASCADE;
CREATE TABLE public.sites (
  id                 UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name               TEXT NOT NULL,
  address            TEXT,
  site_login_id      TEXT UNIQUE NOT NULL,
  site_password_hash TEXT NOT NULL,
  is_active          BOOLEAN DEFAULT TRUE,
  created_by         UUID REFERENCES public.users(id),
  created_at         TIMESTAMPTZ DEFAULT NOW(),
  updated_at         TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- DROPDOWNS TABLE
-- Admin-managed lookup values for form dropdowns
-- ============================================================

DROP TABLE IF EXISTS public.dropdowns CASCADE;
CREATE TABLE public.dropdowns (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  site_id    UUID REFERENCES public.sites(id) ON DELETE CASCADE,
  category   dropdown_category NOT NULL,
  value      TEXT NOT NULL,
  metadata   JSONB DEFAULT '{}',  -- e.g., {"unit": "kg"} for products
  is_active  BOOLEAN DEFAULT TRUE,
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),

  UNIQUE(site_id, category, value)
);

-- ============================================================
-- STOCK TRANSACTIONS TABLE
-- Inbound (Add Product) and Outbound (Use Product)
-- ============================================================

DROP TABLE IF EXISTS public.stock_transactions CASCADE;
CREATE TABLE public.stock_transactions (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  site_id         UUID NOT NULL REFERENCES public.sites(id) ON DELETE RESTRICT,
  submitted_by    UUID NOT NULL REFERENCES public.users(id),
  type            transaction_type NOT NULL,
  date            DATE NOT NULL,

  -- Product & Vendor references
  vendor_id       UUID REFERENCES public.dropdowns(id),       -- NULL for outbound
  product_id      UUID NOT NULL REFERENCES public.dropdowns(id),
  metric_unit_id  UUID NOT NULL REFERENCES public.dropdowns(id),

  -- Quantities & Amounts
  quantity        NUMERIC(12, 3) NOT NULL CHECK (quantity > 0),
  rate            NUMERIC(12, 2),                               -- NULL for outbound
  sgst            NUMERIC(5, 2) DEFAULT 0,                      -- percentage
  igst            NUMERIC(5, 2) DEFAULT 0,                      -- percentage
  final_amount    NUMERIC(14, 2),                               -- auto-calculated or manual

  remarks         TEXT,
  photo_urls      TEXT[] DEFAULT '{}',

  -- Approval workflow
  status          transaction_status NOT NULL DEFAULT 'pending_accounts',
  reviewed_by     UUID REFERENCES public.users(id),             -- accounts user
  approved_by     UUID REFERENCES public.users(id),             -- admin user
  reviewed_at     TIMESTAMPTZ,
  approved_at     TIMESTAMPTZ,
  rejection_note  TEXT,

  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- CASH TRANSACTIONS TABLE
-- ============================================================

DROP TABLE IF EXISTS public.cash_transactions CASCADE;
CREATE TABLE public.cash_transactions (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  site_id          UUID NOT NULL REFERENCES public.sites(id) ON DELETE RESTRICT,
  submitted_by     UUID NOT NULL REFERENCES public.users(id),
  date             DATE NOT NULL,

  -- Expense details
  expense_type_id  UUID NOT NULL REFERENCES public.dropdowns(id),
  expense_amount   NUMERIC(14, 2) NOT NULL DEFAULT 0,
  amount_received  NUMERIC(14, 2) NOT NULL DEFAULT 0,
  cash_in_hand     NUMERIC(14, 2) NOT NULL,

  remarks          TEXT,
  photo_urls       TEXT[] DEFAULT '{}',

  -- Approval workflow
  status           transaction_status NOT NULL DEFAULT 'pending_accounts',
  reviewed_by      UUID REFERENCES public.users(id),
  approved_by      UUID REFERENCES public.users(id),
  reviewed_at      TIMESTAMPTZ,
  approved_at      TIMESTAMPTZ,
  rejection_note   TEXT,

  created_at       TIMESTAMPTZ DEFAULT NOW(),
  updated_at       TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- VIEWS — Real-time Inventory Calculation
-- Current Stock = Sum(Approved Inbound) - Sum(Approved Outbound)
-- ============================================================

DROP VIEW IF EXISTS public.site_current_stock CASCADE;
CREATE VIEW public.site_current_stock AS
SELECT
  st.site_id,
  s.name AS site_name,
  st.product_id,
  d.value AS product_name,
  mu.value AS metric_unit,
  COALESCE(SUM(CASE WHEN st.type = 'inbound'  THEN st.quantity ELSE 0 END), 0)
    AS total_inbound,
  COALESCE(SUM(CASE WHEN st.type = 'outbound' THEN st.quantity ELSE 0 END), 0)
    AS total_outbound,
  COALESCE(SUM(CASE WHEN st.type = 'inbound'  THEN st.quantity ELSE 0 END), 0)
  - COALESCE(SUM(CASE WHEN st.type = 'outbound' THEN st.quantity ELSE 0 END), 0)
    AS current_stock
FROM public.stock_transactions st
JOIN public.sites s ON s.id = st.site_id
JOIN public.dropdowns d ON d.id = st.product_id
JOIN public.dropdowns mu ON mu.id = st.metric_unit_id
WHERE st.status = 'approved'
GROUP BY st.site_id, s.name, st.product_id, d.value, mu.value;

-- ============================================================
-- INDEXES — Performance optimization
-- ============================================================

CREATE INDEX idx_stock_site_status ON public.stock_transactions(site_id, status);
CREATE INDEX idx_stock_product     ON public.stock_transactions(product_id);
CREATE INDEX idx_stock_date        ON public.stock_transactions(date);
CREATE INDEX idx_cash_site_status  ON public.cash_transactions(site_id, status);
CREATE INDEX idx_cash_date         ON public.cash_transactions(date);
CREATE INDEX idx_dropdowns_cat     ON public.dropdowns(category, is_active);

-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.dropdowns ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cash_transactions ENABLE ROW LEVEL SECURITY;

-- ----- USERS -----
CREATE POLICY "Users can read own profile"
  ON public.users FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "Admin full access to users"
  ON public.users FOR ALL
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

-- ----- SITES -----
CREATE POLICY "Everyone can view active sites"
  ON public.sites FOR SELECT
  USING (is_active = TRUE);

CREATE POLICY "Admin manages sites"
  ON public.sites FOR ALL
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

-- ----- DROPDOWNS -----
CREATE POLICY "Everyone can read active dropdowns"
  ON public.dropdowns FOR SELECT
  USING (is_active = TRUE);

CREATE POLICY "Admin manages dropdowns"
  ON public.dropdowns FOR ALL
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

-- ----- STOCK TRANSACTIONS -----

-- Workers: can insert
CREATE POLICY "Worker inserts stock"
  ON public.stock_transactions FOR INSERT
  WITH CHECK (auth.uid() = submitted_by);

-- Workers: can view own submissions
CREATE POLICY "Worker views own stock"
  ON public.stock_transactions FOR SELECT
  USING (auth.uid() = submitted_by);

-- Workers: can edit only if still pending_accounts
CREATE POLICY "Worker edits pending stock"
  ON public.stock_transactions FOR UPDATE
  USING (auth.uid() = submitted_by AND status = 'pending_accounts');

-- Accounts: can view all
CREATE POLICY "Accounts views all stock"
  ON public.stock_transactions FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'accounts')
  );

-- Accounts: can update status (pending_accounts -> pending_admin or rejected)
CREATE POLICY "Accounts reviews stock"
  ON public.stock_transactions FOR UPDATE
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'accounts')
    AND status IN ('pending_accounts', 'pending_admin')
  );

-- Admin: full access
CREATE POLICY "Admin full access stock"
  ON public.stock_transactions FOR ALL
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

-- ----- CASH TRANSACTIONS -----

CREATE POLICY "Worker inserts cash"
  ON public.cash_transactions FOR INSERT
  WITH CHECK (auth.uid() = submitted_by);

CREATE POLICY "Worker views own cash"
  ON public.cash_transactions FOR SELECT
  USING (auth.uid() = submitted_by);

CREATE POLICY "Worker edits pending cash"
  ON public.cash_transactions FOR UPDATE
  USING (auth.uid() = submitted_by AND status = 'pending_accounts');

CREATE POLICY "Accounts views all cash"
  ON public.cash_transactions FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'accounts')
  );

CREATE POLICY "Accounts reviews cash"
  ON public.cash_transactions FOR UPDATE
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'accounts')
    AND status IN ('pending_accounts', 'pending_admin')
  );

CREATE POLICY "Admin full access cash"
  ON public.cash_transactions FOR ALL
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

-- ============================================================
-- TRIGGERS — Auto-update updated_at timestamp
-- ============================================================

CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER trg_sites_updated_at
  BEFORE UPDATE ON public.sites
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER trg_stock_updated_at
  BEFORE UPDATE ON public.stock_transactions
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

CREATE TRIGGER trg_cash_updated_at
  BEFORE UPDATE ON public.cash_transactions
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- ============================================================
-- SEED DATA — Default dropdown values
-- ============================================================

INSERT INTO public.dropdowns (category, value, sort_order) VALUES
  -- Vendors
  ('vendor', 'ABC Suppliers', 1),
  ('vendor', 'XYZ Traders', 2),
  ('vendor', 'Metro Building Materials', 3),
  -- Products
  ('product', 'Cement (OPC 53)', 1),
  ('product', 'TMT Steel Bars', 2),
  ('product', 'Sand (River)', 3),
  ('product', 'Bricks (Red)', 4),
  ('product', 'Aggregate (20mm)', 5),
  ('product', 'Paint (Exterior)', 6),
  -- Metric Units
  ('metric_unit', 'Bags', 1),
  ('metric_unit', 'Kg', 2),
  ('metric_unit', 'Tonnes', 3),
  ('metric_unit', 'Cubic Feet', 4),
  ('metric_unit', 'Pieces', 5),
  ('metric_unit', 'Litres', 6),
  -- Expense Types
  ('expense_type', 'Diesel', 1),
  ('expense_type', 'Food & Refreshments', 2),
  ('expense_type', 'Labour Wages', 3),
  ('expense_type', 'Transportation', 4),
  ('expense_type', 'Miscellaneous', 5);

-- ============================================================
-- STORAGE BUCKETS
-- ============================================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('transaction_photos', 'transaction_photos', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "Authenticated users can upload photos"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'transaction_photos' AND
    auth.role() = 'authenticated'
  );

CREATE POLICY "Authenticated users can view photos"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'transaction_photos' AND
    auth.role() = 'authenticated'
  );

CREATE POLICY "Authenticated users can update own photos"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'transaction_photos' AND
    auth.role() = 'authenticated'
  );
