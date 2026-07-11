import { useEffect, useState } from 'react';

const api = {
  list: () => fetch('/api/todos').then(r => r.json()),
  create: (title) => fetch('/api/todos', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title }),
  }).then(r => r.json()),
  update: (id, patch) => fetch(`/api/todos/${id}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(patch),
  }).then(r => r.json()),
  remove: (id) => fetch(`/api/todos/${id}`, { method: 'DELETE' }),
};

export default function App() {
  const [todos, setTodos] = useState([]);
  const [title, setTitle] = useState('');

  const refresh = () => api.list().then(setTodos);
  useEffect(() => { refresh(); }, []);

  const add = async (e) => {
    e.preventDefault();
    if (!title.trim()) return;
    await api.create(title.trim());
    setTitle('');
    refresh();
  };

  const toggle = async (t) => {
    await api.update(t.id, { done: !t.done });
    refresh();
  };

  const del = async (t) => {
    await api.remove(t.id);
    refresh();
  };

  return (
    <main style={{ fontFamily: 'sans-serif', maxWidth: 480, margin: '2rem auto' }}>
      <h1>To-Do</h1>
      <form onSubmit={add} style={{ display: 'flex', gap: 8 }}>
        <input
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="New task"
          style={{ flex: 1, padding: 8 }}
        />
        <button type="submit">Add</button>
      </form>
      <ul style={{ listStyle: 'none', padding: 0, marginTop: 16 }}>
        {todos.map((t) => (
          <li key={t.id} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '4px 0' }}>
            <input type="checkbox" checked={t.done} onChange={() => toggle(t)} />
            <span style={{ flex: 1, textDecoration: t.done ? 'line-through' : 'none' }}>
              {t.title}
            </span>
            <button onClick={() => del(t)}>x</button>
          </li>
        ))}
      </ul>
    </main>
  );
}
