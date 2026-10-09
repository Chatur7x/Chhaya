#!/usr/bin/env node
/**
 * Chhaya Backend Load Test
 * Simulates 100-1000 concurrent customers to measure efficiency and performance
 * 
 * Usage: node load-test.js [--users=100] [--duration=60] [--rampup=10] [--host=localhost:8443]
 */

import http from 'http';
import https from 'https';
import { performance } from 'perf_hooks';
import crypto from 'crypto';

// Configuration
const config = {
  users: parseInt(process.argv.find(arg => arg.startsWith('--users='))?.split('=')[1]) || 500,
  duration: parseInt(process.argv.find(arg => arg.startsWith('--duration='))?.split('=')[1]) || 60,
  rampup: parseInt(process.argv.find(arg => arg.startsWith('--rampup='))?.split('=')[1]) || 10,
  host: process.argv.find(arg => arg.startsWith('--host='))?.split('=')[1] || 'localhost:8443',
  protocol: 'http',
};

const [host, port] = config.host.split(':');
const baseUrl = `${config.protocol}://${host}:${port}`;

// Test scenarios weights (should sum to 100)
const scenarios = [
  { name: 'register', weight: 15, fn: registerUser },
  { name: 'login', weight: 20, fn: loginUser },
  { name: 'getProfile', weight: 10, fn: getProfile },
  { name: 'addContact', weight: 15, fn: addContact },
  { name: 'getContacts', weight: 10, fn: getContacts },
  { name: 'createConversation', weight: 10, fn: createConversation },
  { name: 'getConversations', weight: 10, fn: getConversations },
  { name: 'sendMessage', weight: 5, fn: sendMessage },
  { name: 'getMessages', weight: 5, fn: getMessages },
];

// Metrics storage
const metrics = {
  totalRequests: 0,
  successfulRequests: 0,
  failedRequests: 0,
  errors: new Map(),
  latencies: [],
  scenarioMetrics: new Map(),
  startTime: 0,
  endTime: 0,
  activeUsers: 0,
  tokens: new Map(), // userId -> token
  userData: new Map(), // userId -> { chhayaId, deviceId }
};

// HTTP client with connection pooling
const agent = new http.Agent({
  keepAlive: true,
  maxSockets: config.users * 2,
  maxFreeSockets: 256,
  timeout: 30000,
  keepAliveMsecs: 1000,
});

function request(method, path, body, token) {
  return new Promise((resolve, reject) => {
    const start = performance.now();
    const requestId = crypto.randomUUID();
    
    const options = {
      hostname: host,
      port: parseInt(port),
      path: `/api/v1${path}`,
      method,
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': 'Chhaya-LoadTest/1.0',
      },
      agent,
      timeout: 30000,
    };

    if (token) {
      options.headers['Authorization'] = `Bearer ${token}`;
    }
    if (body) {
      const bodyStr = JSON.stringify(body);
      options.headers['Content-Length'] = Buffer.byteLength(bodyStr);
    }

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        const latency = performance.now() - start;
        metrics.latencies.push(latency);
        metrics.totalRequests++;
        
        if (res.statusCode >= 200 && res.statusCode < 300) {
          metrics.successfulRequests++;
          try {
            resolve({ status: res.statusCode, data: JSON.parse(data), latency, requestId });
          } catch {
            resolve({ status: res.statusCode, data, latency, requestId });
          }
        } else {
          metrics.failedRequests++;
          const error = `HTTP ${res.statusCode}: ${data}`;
          metrics.errors.set(error, (metrics.errors.get(error) || 0) + 1);
          resolve({ status: res.statusCode, error: data, latency, requestId });
        }
      });
    });

    req.on('error', (err) => {
      const latency = performance.now() - start;
      metrics.latencies.push(latency);
      metrics.totalRequests++;
      metrics.failedRequests++;
      const error = err.code || err.message;
      metrics.errors.set(error, (metrics.errors.get(error) || 0) + 1);
      reject({ error, latency, requestId });
    });

    req.on('timeout', () => {
      req.destroy();
      const latency = performance.now() - start;
      metrics.latencies.push(latency);
      metrics.totalRequests++;
      metrics.failedRequests++;
      metrics.errors.set('timeout', (metrics.errors.get('timeout') || 0) + 1);
      reject({ error: 'timeout', latency });
    });

    if (body) {
      req.write(JSON.stringify(body));
    }
    req.end();
  });
}

// Scenario implementations
async function registerUser(userId) {
  const chhayaId = crypto.randomBytes(33).toString('hex');
  const publicKey = crypto.randomBytes(33).toString('hex');
  const deviceId = crypto.randomUUID();
  
  const res = await request('POST', '/auth/register', {
    chhayaId,
    displayName: `User${userId}`,
    publicKey,
    encryptedPrivateKey: 'encrypted',
    recoveryPhraseHash: crypto.randomBytes(32).toString('hex'),
    deviceId,
    deviceName: 'LoadTest Device',
    platform: 'android',
  });
  
  if (res.status === 201 && res.data?.token) {
    metrics.tokens.set(userId, res.data.token);
    metrics.userData.set(userId, { chhayaId, deviceId });
  }
  return res;
}

async function loginUser(userId) {
  const userData = metrics.userData.get(userId);
  if (!userData) return { status: 400, error: 'No user data' };
  
  const res = await request('POST', '/auth/login', {
    chhayaId: userData.chhayaId,
    recoveryPhraseHash: crypto.randomBytes(32).toString('hex'),
    deviceId: userData.deviceId,
    deviceName: 'LoadTest Device',
    platform: 'android',
  });
  
  if (res.status === 200 && res.data?.token) {
    metrics.tokens.set(userId, res.data.token);
  }
  return res;
}

async function getProfile(userId) {
  const token = metrics.tokens.get(userId);
  if (!token) return { status: 401, error: 'No token' };
  return request('GET', '/users/me', null, token);
}

async function addContact(userId) {
  const token = metrics.tokens.get(userId);
  if (!token) return { status: 401, error: 'No token' };
  
  // Try to add a random user as contact
  const targetId = `chhaya_${crypto.randomBytes(16).toString('hex')}`;
  return request('POST', '/contacts', {
    chhayaId: targetId,
    displayName: `Contact${userId}`,
  }, token);
}

async function getContacts(userId) {
  const token = metrics.tokens.get(userId);
  if (!token) return { status: 401, error: 'No token' };
  return request('GET', '/contacts', null, token);
}

async function createConversation(userId) {
  const token = metrics.tokens.get(userId);
  if (!token) return { status: 401, error: 'No token' };
  
  return request('POST', '/conversations', {
    type: 'direct',
    participantIds: [crypto.randomUUID()],
  }, token);
}

async function getConversations(userId) {
  const token = metrics.tokens.get(userId);
  if (!token) return { status: 401, error: 'No token' };
  return request('GET', '/conversations', null, token);
}

async function sendMessage(userId) {
  const token = metrics.tokens.get(userId);
  if (!token) return { status: 401, error: 'No token' };
  
  return request('POST', '/messages', {
    conversationId: crypto.randomUUID(),
    content: `Test message from user ${userId} at ${Date.now()}`,
    messageType: 'text',
  }, token);
}

async function getMessages(userId) {
  const token = metrics.tokens.get(userId);
  if (!token) return { status: 401, error: 'No token' };
  
  return request('GET', `/messages/${crypto.randomUUID()}`, null, token);
}

// Metrics helpers
function percentile(arr, p) {
  if (arr.length === 0) return 0;
  const sorted = [...arr].sort((a, b) => a - b);
  const idx = Math.ceil(p / 100 * sorted.length) - 1;
  return sorted[Math.max(0, idx)];
}

function printReport() {
  const elapsed = (metrics.endTime - metrics.startTime) / 1000;
  const rps = metrics.totalRequests / elapsed;
  
  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('           CHHAYA BACKEND LOAD TEST REPORT');
  console.log('═══════════════════════════════════════════════════════════');
  
  console.log('\n📊 TEST CONFIGURATION');
  console.log(`   Target Users:        ${config.users}`);
  console.log(`   Test Duration:       ${config.duration}s`);
  console.log(`   Ramp-up Period:      ${config.rampup}s`);
  console.log(`   Target Host:         ${config.host}`);
  console.log(`   Actual Users:        ${metrics.activeUsers}`);
  
  console.log('\n📈 OVERALL METRICS');
  console.log(`   Total Requests:      ${metrics.totalRequests}`);
  console.log(`   Successful:          ${metrics.successfulRequests} (${((metrics.successfulRequests/metrics.totalRequests)*100).toFixed(2)}%)`);
  console.log(`   Failed:              ${metrics.failedRequests} (${((metrics.failedRequests/metrics.totalRequests)*100).toFixed(2)}%)`);
  console.log(`   Requests/sec:        ${rps.toFixed(2)}`);
  console.log(`   Avg Latency:         ${(metrics.latencies.reduce((a,b)=>a+b,0)/metrics.latencies.length).toFixed(2)}ms`);
  
  console.log('\n⏱️  LATENCY PERCENTILES');
  console.log(`   p50:                 ${percentile(metrics.latencies, 50).toFixed(2)}ms`);
  console.log(`   p75:                 ${percentile(metrics.latencies, 75).toFixed(2)}ms`);
  console.log(`   p90:                 ${percentile(metrics.latencies, 90).toFixed(2)}ms`);
  console.log(`   p95:                 ${percentile(metrics.latencies, 95).toFixed(2)}ms`);
  console.log(`   p99:                 ${percentile(metrics.latencies, 99).toFixed(2)}ms`);
  console.log(`   max:                 ${Math.max(...metrics.latencies).toFixed(2)}ms`);
  
  console.log('\n🔍 ERROR BREAKDOWN');
  if (metrics.errors.size === 0) {
    console.log('   No errors recorded');
  } else {
    for (const [error, count] of metrics.errors.entries()) {
      console.log(`   ${error}: ${count}`);
    }
  }
  
  console.log('\n🎯 SCENARIO BREAKDOWN');
  for (const [scenario, data] of metrics.scenarioMetrics.entries()) {
    const total = data.success + data.failed;
    const avgLatency = data.latencies.length > 0 
      ? data.latencies.reduce((a,b)=>a+b,0)/data.latencies.length 
      : 0;
    console.log(`   ${scenario}: ${total} req (${data.success}✓ ${data.failed}✗) | avg: ${avgLatency.toFixed(2)}ms`);
  }
  
  console.log('\n💾 RESOURCE EFFICIENCY');
  const memUsage = process.memoryUsage();
  console.log(`   RSS:                 ${(memUsage.rss/1024/1024).toFixed(2)} MB`);
  console.log(`   Heap Used:           ${(memUsage.heapUsed/1024/1024).toFixed(2)} MB`);
  console.log(`   Heap Total:          ${(memUsage.heapTotal/1024/1024).toFixed(2)} MB`);
  console.log(`   External:            ${(memUsage.external/1024/1024).toFixed(2)} MB`);
  
  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('                    TEST COMPLETE');
  console.log('═══════════════════════════════════════════════════════════\n');
}

// User simulation
async function simulateUser(userId) {
  metrics.activeUsers++;
  
  try {
    // Initial registration/login
    await registerUser(userId);
    await new Promise(r => setTimeout(r, Math.random() * 1000));
    await loginUser(userId);
    
    const endTime = metrics.startTime + config.duration * 1000;
    
    while (Date.now() < endTime) {
      // Pick scenario based on weights
      const rand = Math.random() * 100;
      let cumulative = 0;
      let selectedScenario = null;
      
      for (const s of scenarios) {
        cumulative += s.weight;
        if (rand <= cumulative) {
          selectedScenario = s;
          break;
        }
      }
      
      if (!selectedScenario) continue;
      
      const scenarioStart = performance.now();
      let result;
      
      try {
        result = await selectedScenario.fn(userId);
      } catch (err) {
        result = { status: 0, error: err.message };
      }
      
      const scenarioLatency = performance.now() - scenarioStart;
      
      // Track scenario metrics
      const sm = metrics.scenarioMetrics.get(selectedScenario.name) || { 
        success: 0, failed: 0, latencies: [] 
      };
      sm.latencies.push(scenarioLatency);
      if (result.status >= 200 && result.status < 300) {
        sm.success++;
      } else {
        sm.failed++;
      }
      metrics.scenarioMetrics.set(selectedScenario.name, sm);
      
      // Think time between requests (100-500ms)
      await new Promise(r => setTimeout(r, 100 + Math.random() * 400));
    }
  } finally {
    metrics.activeUsers--;
  }
}

// Main load test runner
async function runLoadTest() {
  console.log('═══════════════════════════════════════════════════════════');
  console.log('       CHHAYA BACKEND LOAD TEST STARTING');
  console.log('═══════════════════════════════════════════════════════════');
  console.log(`\n🚀 Starting with ${config.users} users over ${config.duration}s`);
  console.log(`   Ramp-up: ${config.rampup}s | Target: ${config.host}\n`);
  
  metrics.startTime = Date.now();
  
  // Health check first
  console.log('🔍 Running health check...');
  const health = await request('GET', '/health');
  if (health.status !== 200) {
    console.error('❌ Health check failed:', health);
    process.exit(1);
  }
  console.log('✅ Health check passed\n');
  
  // Ramp up users gradually
  const userPromises = [];
  const rampInterval = (config.rampup * 1000) / config.users;
  
  for (let i = 0; i < config.users; i++) {
    const userId = `user_${i}`;
    userPromises.push(simulateUser(userId));
    
    if (i < config.users - 1) {
      await new Promise(r => setTimeout(r, rampInterval));
    }
  }
  
  console.log(`\n✅ All ${config.users} users ramped up. Running for ${config.duration}s...`);
  
  // Wait for test duration
  await new Promise(r => setTimeout(r, config.duration * 1000));
  
  metrics.endTime = Date.now();
  
  // Wait for all user simulations to complete
  await Promise.allSettled(userPromises);
  
  printReport();
  
  // Exit code based on success rate
  const successRate = metrics.successfulRequests / metrics.totalRequests;
  process.exit(successRate >= 0.95 ? 0 : 1);
}

// Handle graceful shutdown
process.on('SIGINT', () => {
  console.log('\n🛑 Interrupted. Generating report...');
  metrics.endTime = Date.now();
  printReport();
  process.exit(0);
});

runLoadTest().catch(err => {
  console.error('Fatal error:', err);
  process.exit(1);
});