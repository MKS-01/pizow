# Node.js API Example

Minimal Express API for Raspberry Pi Zero W. No database required - uses in-memory storage for demo.

## Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check with uptime |
| GET | `/info` | Server info (Node version, memory) |
| POST | `/echo` | Echo back request body |
| GET | `/notes` | List all notes |
| GET | `/notes/:id` | Get single note |
| POST | `/notes` | Create note |
| DELETE | `/notes/:id` | Delete note |

## Local Development

```bash
npm install
npm run dev
```

Server runs at [http://localhost:3000](http://localhost:3000)

## Test Endpoints

```bash
# Health check
curl http://localhost:3000/health

# Server info
curl http://localhost:3000/info

# Echo test
curl -X POST http://localhost:3000/echo \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello Pi!"}'

# List notes
curl http://localhost:3000/notes

# Create note
curl -X POST http://localhost:3000/notes \
  -H "Content-Type: application/json" \
  -d '{"title": "Test", "content": "My first note"}'

# Delete note
curl -X DELETE http://localhost:3000/notes/1
```

## Deploy to Pi

```bash
# On your Pi
git clone https://github.com/YOUR_USERNAME/pizow.git
cd pizow/examples/node-api
npm install
pm2 start server.js --name "node-api"

# Configure Nginx
cd ~/pizow
./scripts/nginx-setup.sh node-api 3000
```

## Project Structure

```
examples/node-api/
├── server.js        # Express server with all endpoints
├── package.json
├── .env.example
└── README.md
```
