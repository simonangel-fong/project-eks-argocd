import express from 'express';
import pg from 'pg';

const { Pool } = pg;

const pool = new Pool({
  host: process.env.PGHOST || 'localhost',
  port: Number(process.env.PGPORT || 5432),
  user: process.env.PGUSER || 'todo',
  password: process.env.PGPASSWORD || 'todo',
  database: process.env.PGDATABASE || 'todo',
});

const app = express();
app.use(express.json());

app.get('/healthz', (_req, res) => res.json({ ok: true }));

app.get('/api/todos', async (_req, res, next) => {
  try {
    const { rows } = await pool.query(
      'SELECT id, title, done, created_at FROM todos ORDER BY id DESC'
    );
    res.json(rows);
  } catch (e) { next(e); }
});

app.post('/api/todos', async (req, res, next) => {
  try {
    const { title } = req.body;
    if (!title) return res.status(400).json({ error: 'title required' });
    const { rows } = await pool.query(
      'INSERT INTO todos (title) VALUES ($1) RETURNING id, title, done, created_at',
      [title]
    );
    res.status(201).json(rows[0]);
  } catch (e) { next(e); }
});

app.put('/api/todos/:id', async (req, res, next) => {
  try {
    const { title, done } = req.body;
    const { rows } = await pool.query(
      `UPDATE todos
         SET title = COALESCE($1, title),
             done  = COALESCE($2, done)
       WHERE id = $3
       RETURNING id, title, done, created_at`,
      [title ?? null, done ?? null, req.params.id]
    );
    if (!rows[0]) return res.status(404).json({ error: 'not found' });
    res.json(rows[0]);
  } catch (e) { next(e); }
});

app.delete('/api/todos/:id', async (req, res, next) => {
  try {
    const { rowCount } = await pool.query('DELETE FROM todos WHERE id = $1', [req.params.id]);
    if (!rowCount) return res.status(404).json({ error: 'not found' });
    res.status(204).end();
  } catch (e) { next(e); }
});

app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ error: 'internal error' });
});

const port = Number(process.env.PORT || 3000);
app.listen(port, () => console.log(`todo-api listening on ${port}`));
