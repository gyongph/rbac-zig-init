CREATE TABLE account
(
    id TEXT PRIMARY KEY,
    xa_id TEXT NOT NULL,
    xa_perm_refresh_token TEXT NOT NULL,
    xa_perm_rt_created_at TIMESTAMPTZ NOT NULL,
    xa_perm_rt_expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ default current_timestamp
);