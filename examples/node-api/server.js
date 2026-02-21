const express = require('express');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(express.json());

// Store for demo (in-memory, resets on restart)
const notes = [
  { id: 1, title: 'Welcome', content: 'Your Pi Zero server is running!' },
  { id: 2, title: 'Get Started', content: 'Try the API endpoints below.' }
];

// ===========================================
// Endpoints
// ===========================================

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    uptime: process.uptime(),
    timestamp: new Date().toISOString()
  });
});

// Server info
app.get('/info', (req, res) => {
  res.json({
    name: 'PiZoW API',
    version: '1.0.0',
    node: process.version,
    platform: process.platform,
    arch: process.arch,
    memory: {
      used: Math.round(process.memoryUsage().heapUsed / 1024 / 1024) + 'MB',
      total: Math.round(process.memoryUsage().heapTotal / 1024 / 1024) + 'MB'
    }
  });
});

// Echo endpoint (POST)
app.post('/echo', (req, res) => {
  res.json({
    received: req.body,
    timestamp: new Date().toISOString()
  });
});

// ===========================================
// Notes CRUD (demo without DB)
// ===========================================

// Get all notes
app.get('/notes', (req, res) => {
  res.json(notes);
});

// Get single note
app.get('/notes/:id', (req, res) => {
  const note = notes.find(n => n.id === parseInt(req.params.id));
  if (!note) {
    return res.status(404).json({ error: 'Note not found' });
  }
  res.json(note);
});

// Create note
app.post('/notes', (req, res) => {
  const { title, content } = req.body;
  if (!title || !content) {
    return res.status(400).json({ error: 'Title and content required' });
  }
  const note = {
    id: notes.length + 1,
    title,
    content
  };
  notes.push(note);
  res.status(201).json(note);
});

// Delete note
app.delete('/notes/:id', (req, res) => {
  const index = notes.findIndex(n => n.id === parseInt(req.params.id));
  if (index === -1) {
    return res.status(404).json({ error: 'Note not found' });
  }
  notes.splice(index, 1);
  res.json({ message: 'Note deleted' });
});

// ===========================================
// 404 handler
// ===========================================
app.use((req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// ===========================================
// Start server
// ===========================================
app.listen(PORT, () => {
  console.log(`
  ┌─────────────────────────────────────┐
  │   PiZoW API Server                  │
  │   Running on http://localhost:${PORT}  │
  └─────────────────────────────────────┘

  Endpoints:
    GET  /health     - Health check
    GET  /info       - Server info
    POST /echo       - Echo request body

    GET  /notes      - List all notes
    GET  /notes/:id  - Get single note
    POST /notes      - Create note
    DELETE /notes/:id - Delete note
  `);
});
