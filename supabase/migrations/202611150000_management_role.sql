-- Add the role label before any later migration uses it. Existing role values are unchanged.
alter type public.user_role add value if not exists 'project_head';
