const express = require('express');
const cors = require('cors');
const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

const counters = {
  'different-devices': 0,
  'same-device': 0
};

app.get('/stats', (req, res) => {
  res.json(counters);
});

app.get('/stats/:counter', (req, res) => {
  const { counter } = req.params;
  if (counters.hasOwnProperty(counter)) {
    res.json({ count: counters[counter] });
  } else {
    res.status(404).json({ error: 'Counter not found' });
  }
});

app.post('/stats/:counter/increment', (req, res) => {
  const { counter } = req.params;
  if (counters.hasOwnProperty(counter)) {
    counters[counter]++;
    res.json({ count: counters[counter] });
  } else {
    counters[counter] = 1;
    res.json({ count: counters[counter] });
  }
});

app.get('/different-devices', (req, res) => {
  res.json({ count: counters['different-devices'] });
});

app.get('/same-device', (req, res) => {
  res.json({ count: counters['same-device'] });
});

app.post('/different-devices/increment', (req, res) => {
  counters['different-devices']++;
  res.json({ count: counters['different-devices'] });
});

app.post('/same-device/increment', (req, res) => {
  counters['same-device']++;
  res.json({ count: counters['same-device'] });
});

app.get('/', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <title>Catus Chat Stats</title>
      <style>
        body { font-family: Arial, sans-serif; text-align: center; padding: 50px; background: #1a1a2e; color: white; }
        .stat { font-size: 48px; margin: 20px; }
        .label { font-size: 18px; color: #888; }
        .container { display: flex; justify-content: center; gap: 50px; }
        .card { background: #16213e; padding: 30px; border-radius: 15px; }
      </style>
    </head>
    <body>
      <h1>🌑 Catus Chat MeshLink Stats</h1>
      <div class="container">
        <div class="card">
          <div class="label">Mesh Networks Created</div>
          <div class="stat" id="different-devices">${counters['different-devices']}</div>
        </div>
        <div class="card">
          <div class="label">Active Testers</div>
          <div class="stat" id="same-device">${counters['same-device']}</div>
        </div>
      </div>
      <p style="margin-top: 50px; color: #666;">
        Use POST /{counter}/increment to track installs<br>
        Example: curl -X POST https://your-backend.railway.app/different-devices/increment
      </p>
      <script>
        setInterval(() => {
          fetch('/stats')
            .then(r => r.json())
            .then(data => {
              document.getElementById('different-devices').textContent = data['different-devices'];
              document.getElementById('same-device').textContent = data['same-device'];
            });
        }, 5000);
      </script>
    </body>
    </html>
  `);
});

app.listen(PORT, () => {
  console.log(`🌑 Catus Chat Counter Backend running on port ${PORT}`);
});
