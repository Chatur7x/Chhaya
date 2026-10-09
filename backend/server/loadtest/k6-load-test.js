// k6 Load Test Script for Chhaya Backend
// Run with: k6 run --vus 500 --duration 60s k6-load-test.js

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';
import { SharedArray } from 'k6/data';

// Custom metrics
const errorRate = new Rate('errors');
const loginRate = new Rate('login_success');
const registerRate = new Rate('register_success');
const messageRate = new Rate('message_success');
const latency = new Trend('latency');
const activeUsers = new Counter('active_users');

// Test configuration
export const options = {
  scenarios: {
    ramp_up: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 100 },   // Ramp to 100
        { duration: '30s', target: 250 },   // Ramp to 250
        { duration: '30s', target: 500 },   // Ramp to 500
        { duration: '30s', target: 750 },   // Ramp to 750
        { duration: '30s', target: 1000 },  // Ramp to 1000
        { duration: '60s', target: 1000 },  // Hold at 1000
        { duration: '30s', target: 0 },     // Ramp down
      ],
      gracefulRampDown: '10s',
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    http_req_failed: ['rate<0.05'],
    errors: ['rate<0.05'],
    login_success: ['rate>0.95'],
    register_success: ['rate>0.95'],
    message_success: ['rate>0.95'],
  },
};

// Base URL - override with: k6 run -e BASE_URL=https://api.chhaya.app k6-load-test.js
const BASE_URL = __ENV.BASE_URL || 'http://localhost:8443';

// Shared test data
const testUsers = new SharedArray('test users', function() {
  const users = [];
  for (let i = 0; i < 2000; i++) {
    users.push({
      id: i,
      chhayaId: `chhaya_${crypto.randomBytes(16).toString('hex')}`,
      displayName: `User${i}`,
      publicKey: crypto.randomBytes(33).toString('hex'),
      recoveryPhraseHash: crypto.randomBytes(32).toString('hex'),
      deviceId: crypto.randomUUID(),
    });
  }
  return users;
});

// Global storage for tokens
const userTokens = new Map();
const userData = new Map();

function randomUser() {
  return testUsers[Math.floor(Math.random() * testUsers.length)];
}

function getHeaders(token) {
  const headers = {
    'Content-Type': 'application/json',
    'User-Agent': 'Chhaya-LoadTest/k6',
  };
  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }
  return headers;
}

export function setup() {
  // Verify health endpoint
  const health = http.get(`${BASE_URL}/api/v1/health`);
  check(health, { 'health check ok': (r) => r.status === 200 });
  
  // Pre-register some users for login testing
  const preRegistered = [];
  for (let i = 0; i < 500; i++) {
    const user = testUsers[i];
    const res = http.post(`${BASE_URL}/api/v1/auth/register`, JSON.stringify({
      chhayaId: user.chhayaId,
      displayName: user.displayName,
      publicKey: user.publicKey,
      encryptedPrivateKey: 'encrypted',
      recoveryPhraseHash: user.recoveryPhraseHash,
      deviceId: user.deviceId,
      deviceName: 'LoadTest Device',
      platform: 'android',
    }), { headers: getHeaders() });
    
    if (res.status === 201 && res.json('token')) {
      preRegistered.push({ user, token: res.json('token') });
    }
    sleep(0.01);
  }
  
  return { preRegistered };
}

export default function (data) {
  const user = randomUser();
  const userId = user.id;
  const token = data.preRegistered?.find(u => u.user.id === userId)?.token;
  
  // Track active user
  activeUsers.add(1);
  
  // Scenario selection based on weights
  const rand = Math.random() * 100;
  
  if (rand < 15) {
    // Register (15%)
    const newUser = {
      ...user,
      chhayaId: `chhaya_${crypto.randomBytes(16).toString('hex')}`,
    };
    const res = http.post(`${BASE_URL}/api/v1/auth/register`, JSON.stringify({
      chhayaId: newUser.chhayaId,
      displayName: newUser.displayName,
      publicKey: newUser.publicKey,
      encryptedPrivateKey: 'encrypted',
      recoveryPhraseHash: newUser.recoveryPhraseHash,
      deviceId: newUser.deviceId,
      deviceName: 'LoadTest Device',
      platform: 'android',
    }), { headers: getHeaders() });
    
    const success = check(res, {
      'register status 201': (r) => r.status === 201,
      'register has token': (r) => r.json('token') !== undefined,
    });
    registerRate.add(success);
    errorRate.add(!success);
    latency.add(res.timings.duration);
    
  } else if (rand < 35) {
    // Login (20%)
    const loginRes = http.post(`${BASE_URL}/api/v1/auth/login`, JSON.stringify({
      chhayaId: user.chhayaId,
      recoveryPhraseHash: user.recoveryPhraseHash,
      deviceId: user.deviceId,
      deviceName: 'LoadTest Device',
      platform: 'android',
    }), { headers: getHeaders() });
    
    const loginSuccess = check(loginRes, {
      'login status 200': (r) => r.status === 200,
      'login has token': (r) => r.json('token') !== undefined,
    });
    loginRate.add(loginSuccess);
    errorRate.add(!loginSuccess);
    latency.add(loginRes.timings.duration);
    
    if (loginSuccess && loginRes.json('token')) {
      userTokens.set(userId, loginRes.json('token'));
    }
    
  } else if (rand < 45) {
    // Get Profile (10%)
    const userToken = userTokens.get(userId) || (data.preRegistered?.find(u => u.user.id === userId)?.token);
    if (userToken) {
      const res = http.get(`${BASE_URL}/api/v1/users/me`, { headers: getHeaders(userToken) });
      check(res, { 'profile status 200': (r) => r.status === 200 });
      errorRate.add(res.status !== 200);
      latency.add(res.timings.duration);
    }
    
  } else if (rand < 60) {
    // Add Contact (15%)
    const userToken = userTokens.get(userId) || (data.preRegistered?.find(u => u.user.id === userId)?.token);
    if (userToken) {
      const targetId = `chhaya_${crypto.randomBytes(16).toString('hex')}`;
      const res = http.post(`${BASE_URL}/api/v1/contacts`, JSON.stringify({
        chhayaId: targetId,
        displayName: `Contact${userId}`,
      }), { headers: getHeaders(userToken) });
      
      check(res, { 'add contact 201': (r) => r.status === 201 || r.status === 409 });
      errorRate.add(res.status >= 500);
      latency.add(res.timings.duration);
    }
    
  } else if (rand < 70) {
    // Get Contacts (10%)
    const userToken = userTokens.get(userId) || (data.preRegistered?.find(u => u.user.id === userId)?.token);
    if (userToken) {
      const res = http.get(`${BASE_URL}/api/v1/contacts`, { headers: getHeaders(userToken) });
      check(res, { 'contacts 200': (r) => r.status === 200 });
      errorRate.add(res.status !== 200);
      latency.add(res.timings.duration);
    }
    
  } else if (rand < 80) {
    // Create Conversation (10%)
    const userToken = userTokens.get(userId) || (data.preRegistered?.find(u => u.user.id === userId)?.token);
    if (userToken) {
      const res = http.post(`${BASE_URL}/api/v1/conversations`, JSON.stringify({
        type: 'direct',
        participantIds: [crypto.randomUUID()],
      }), { headers: getHeaders(userToken) });
      
      check(res, { 'conversation 201': (r) => r.status === 201 });
      errorRate.add(res.status !== 201);
      latency.add(res.timings.duration);
    }
    
  } else if (rand < 90) {
    // Get Conversations (10%)
    const userToken = userTokens.get(userId) || (data.preRegistered?.find(u => u.user.id === userId)?.token);
    if (userToken) {
      const res = http.get(`${BASE_URL}/api/v1/conversations`, { headers: getHeaders(userToken) });
      check(res, { 'conversations 200': (r) => r.status === 200 });
      errorRate.add(res.status !== 200);
      latency.add(res.timings.duration);
    }
    
  } else if (rand < 95) {
    // Send Message (5%)
    const userToken = userTokens.get(userId) || (data.preRegistered?.find(u => u.user.id === userId)?.token);
    if (userToken) {
      const res = http.post(`${BASE_URL}/api/v1/messages`, JSON.stringify({
        conversationId: crypto.randomUUID(),
        content: `Test message from user ${userId} at ${Date.now()}`,
        messageType: 'text',
      }), { headers: getHeaders(userToken) });
      
      const success = check(res, { 'message 201': (r) => r.status === 201 });
      messageRate.add(success);
      errorRate.add(!success);
      latency.add(res.timings.duration);
    }
    
  } else {
    // Get Messages (5%)
    const userToken = userTokens.get(userId) || (data.preRegistered?.find(u => u.user.id === userId)?.token);
    if (userToken) {
      const res = http.get(`${BASE_URL}/api/v1/messages/${crypto.randomUUID()}`, { headers: getHeaders(userToken) });
      check(res, { 'messages 200': (r) => r.status === 200 });
      errorRate.add(res.status !== 200);
      latency.add(res.timings.duration);
    }
  }
  
  // Think time
  sleep(Math.random() * 0.4 + 0.1);
}

export function teardown(data) {
  // Summary is automatically printed by k6
  console.log('Load test completed');
}