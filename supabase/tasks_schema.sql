-- Schema for Tasks and Task Comments

-- Enum for Task Status
CREATE TYPE task_status AS ENUM ('pending', 'in_progress', 'completed', 'verified');

-- Enum for Task Priority
CREATE TYPE task_priority AS ENUM ('low', 'medium', 'high');

-- Tasks Table
CREATE TABLE tasks (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    site_id UUID NOT NULL REFERENCES sites(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    assigned_to UUID REFERENCES users(id) ON DELETE SET NULL,
    created_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status task_status DEFAULT 'pending',
    priority task_priority DEFAULT 'medium',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Trigger to update 'updated_at' on Tasks
CREATE OR REPLACE FUNCTION update_task_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tasks_updated_at_trigger
BEFORE UPDATE ON tasks
FOR EACH ROW
EXECUTE FUNCTION update_task_updated_at();

-- Task Comments Table
CREATE TABLE task_comments (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    task_id UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    image_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- RLS Policies for Tasks
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;

-- Admins and Accounts can see all tasks, Workers can see tasks assigned to them or for their sites.
-- For simplicity, assuming users can read tasks for sites they have access to. 
-- Adjust this based on your exact RLS logic.
CREATE POLICY "Users can read tasks" ON tasks FOR SELECT USING (true);
CREATE POLICY "Admins can insert tasks" ON tasks FOR INSERT WITH CHECK (true);
CREATE POLICY "Users can update tasks" ON tasks FOR UPDATE USING (true);

-- RLS Policies for Task Comments
ALTER TABLE task_comments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read task comments" ON task_comments FOR SELECT USING (true);
CREATE POLICY "Users can insert task comments" ON task_comments FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Make sure to allow real-time replication for task_comments
-- so the chat feature works via Supabase Streams.
ALTER PUBLICATION supabase_realtime ADD TABLE task_comments;
ALTER PUBLICATION supabase_realtime ADD TABLE tasks;
