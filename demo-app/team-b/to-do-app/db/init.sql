CREATE TABLE IF NOT EXISTS todos (
  id          SERIAL PRIMARY KEY,
  title       TEXT NOT NULL,
  done        BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO todos (title, done) VALUES
  ('Deploy EKS cluster', TRUE),
  ('Wire up ArgoCD', TRUE),
  ('Ship canary rollout', FALSE);
