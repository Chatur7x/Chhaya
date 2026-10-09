#!/usr/bin/env node
/**
 * Chhaya Load Test Results Analyzer
 * Processes load test results and generates efficiency/performance report
 * 
 * Usage: node analyze-results.js <results-file.json>
 */

import fs from 'fs';
import path from 'path';

function analyzeResults(resultsPath) {
  if (!fs.existsSync(resultsPath)) {
    console.error(`Results file not found: ${resultsPath}`);
    process.exit(1);
  }

  const data = JSON.parse(fs.readFileSync(resultsPath, 'utf8'));
  
  console.log('═══════════════════════════════════════════════════════════');
  console.log('       CHHAYA LOAD TEST EFFICIENCY ANALYSIS REPORT');
  console.log('═══════════════════════════════════════════════════════════\n');

  // Overall metrics
  const metrics = data.metrics || data;
  const totalRequests = metrics.http_reqs?.count || metrics.totalRequests || 0;
  const failedRequests = metrics.http_req_failed?.count || metrics.failedRequests || 0;
  const successRate = totalRequests > 0 ? ((totalRequests - failedRequests) / totalRequests * 100).toFixed(2) : 0;
  
  const duration = metrics.http_req_duration || metrics.latencies || {};
  const avgLatency = duration.mean || (metrics.latencies?.reduce((a,b)=>a+b,0) / metrics.latencies.length) || 0;
  const p50 = duration['p(50)'] || percentile(metrics.latencies, 50);
  const p90 = duration['p(90)'] || percentile(metrics.latencies, 90);
  const p95 = duration['p(95)'] || percentile(metrics.latencies, 95);
  const p99 = duration['p(99)'] || percentile(metrics.latencies, 99);
  const maxLatency = duration.max || Math.max(...(metrics.latencies || [0]));

  const rps = metrics.http_reqs?.rate || (totalRequests / (metrics.duration || 1));

  console.log('📊 OVERALL EFFICIENCY METRICS');
  console.log('─────────────────────────────');
  console.log(`Total Requests:        ${totalRequests.toLocaleString()}`);
  console.log(`Successful Requests:   ${(totalRequests - failedRequests).toLocaleString()}`);
  console.log(`Failed Requests:       ${failedRequests.toLocaleString()}`);
  console.log(`Success Rate:          ${successRate}%`);
  console.log(`Requests/Second (RPS): ${rps.toFixed(2)}`);
  console.log(`Test Duration:         ${(metrics.duration / 1000).toFixed(1)}s`);
  console.log(`Concurrent Users:      ${metrics.active_users?.max || metrics.maxUsers || 'N/A'}`);

  console.log('\n⏱️  LATENCY DISTRIBUTION');
  console.log('─────────────────────────────');
  console.log(`Average:               ${avgLatency.toFixed(2)}ms`);
  console.log(`Median (p50):          ${p50.toFixed(2)}ms`);
  console.log(`p90:                   ${p90.toFixed(2)}ms`);
  console.log(`p95:                   ${p95.toFixed(2)}ms`);
  console.log(`p99:                   ${p99.toFixed(2)}ms`);
  console.log(`Max:                   ${maxLatency.toFixed(2)}ms`);

  // Latency efficiency score (lower is better)
  const latencyScore = calculateLatencyScore(p50, p95, p99);
  console.log(`\n🎯 LATENCY EFFICIENCY SCORE: ${latencyScore}/100`);

  // Throughput efficiency
  const throughputScore = calculateThroughputScore(rps, totalRequests, metrics.duration || 60000);
  console.log(`📈 THROUGHPUT EFFICIENCY SCORE: ${throughputScore}/100`);

  // Error efficiency
  const errorRate = (failedRequests / totalRequests * 100).toFixed(2);
  const errorScore = calculateErrorScore(errorRate);
  console.log(`❌ ERROR RESILIENCE SCORE: ${errorScore}/100`);

  // Resource efficiency (if available)
  if (metrics.memory) {
    console.log('\n💾 RESOURCE EFFICIENCY');
    console.log('─────────────────────────────');
    console.log(`Memory RSS:            ${(metrics.memory.rss / 1024 / 1024).toFixed(2)} MB`);
    console.log(`Heap Used:             ${(metrics.memory.heapUsed / 1024 / 1024).toFixed(2)} MB`);
    console.log(`CPU Usage:             ${metrics.cpu?.toFixed(2) || 'N/A'}%`);
  }

  // Scenario breakdown
  if (metrics.scenarios) {
    console.log('\n📋 SCENARIO EFFICIENCY BREAKDOWN');
    console.log('─────────────────────────────');
    console.log('Scenario              | Requests | Success% | Avg Latency | RPS');
    console.log('─────────────────────|──────────|──────────|─────────────|─────');
    
    for (const [name, data] of Object.entries(metrics.scenarios)) {
      const sRate = data.total > 0 ? (data.success / data.total * 100).toFixed(1) : 0;
      const avgLat = data.latencies?.length > 0 
        ? (data.latencies.reduce((a,b)=>a+b,0) / data.latencies.length).toFixed(1) 
        : 'N/A';
      const sRps = data.total / (metrics.duration / 1000);
      console.log(`${name.padEnd(20)} | ${data.total.toString().padStart(8)} | ${sRate.padStart(6)}% | ${avgLat.toString().padStart(11)} | ${sRps.toFixed(1)}`);
    }
  }

  // Overall efficiency rating
  const overallScore = Math.round((latencyScore + throughputScore + errorScore) / 3);
  const rating = getEfficiencyRating(overallScore);
  
  console.log('\n═══════════════════════════════════════════════════════════');
  console.log(`       OVERALL EFFICIENCY SCORE: ${overallScore}/100 (${rating})`);
  console.log('═══════════════════════════════════════════════════════════\n');

  // Recommendations
  console.log('💡 OPTIMIZATION RECOMMENDATIONS');
  console.log('─────────────────────────────');
  generateRecommendations(p50, p95, p99, rps, errorRate, successRate);

  // Save summary JSON
  const summary = {
    timestamp: new Date().toISOString(),
    overallScore,
    rating,
    metrics: {
      totalRequests,
      successRate: parseFloat(successRate),
      rps: parseFloat(rps.toFixed(2)),
      latency: {
        avg: parseFloat(avgLatency.toFixed(2)),
        p50: parseFloat(p50.toFixed(2)),
        p90: parseFloat(p90.toFixed(2)),
        p95: parseFloat(p95.toFixed(2)),
        p99: parseFloat(p99.toFixed(2)),
        max: parseFloat(maxLatency.toFixed(2)),
      },
      errorRate: parseFloat(errorRate),
      scores: {
        latency: latencyScore,
        throughput: throughputScore,
        errorResilience: errorScore,
      }
    }
  };

  const outputPath = resultsPath.replace('.json', '-analysis.json');
  fs.writeFileSync(outputPath, JSON.stringify(summary, null, 2));
  console.log(`\n📄 Analysis saved to: ${outputPath}`);
}

function percentile(arr, p) {
  if (!arr || arr.length === 0) return 0;
  const sorted = [...arr].sort((a, b) => a - b);
  const idx = Math.ceil(p / 100 * sorted.length) - 1;
  return sorted[Math.max(0, idx)];
}

function calculateLatencyScore(p50, p95, p99) {
  // Ideal: p50 < 50ms, p95 < 200ms, p99 < 500ms
  let score = 100;
  if (p50 > 50) score -= Math.min(30, (p50 - 50) / 10);
  if (p95 > 200) score -= Math.min(30, (p95 - 200) / 20);
  if (p99 > 500) score -= Math.min(40, (p99 - 500) / 50);
  return Math.max(0, Math.round(score));
}

function calculateThroughputScore(rps, totalRequests, durationMs) {
  // Target: >100 RPS per 100 users
  const users = 500; // assume
  const targetRps = users * 0.2; // 100 RPS per 100 users = 0.2 RPS per user
  const ratio = rps / targetRps;
  return Math.min(100, Math.round(ratio * 100));
}

function calculateErrorScore(errorRate) {
  // Target: <1% error rate
  if (errorRate < 0.1) return 100;
  if (errorRate < 0.5) return 95;
  if (errorRate < 1) return 90;
  if (errorRate < 2) return 75;
  if (errorRate < 5) return 50;
  return Math.max(0, 100 - errorRate * 10);
}

function getEfficiencyRating(score) {
  if (score >= 90) return 'EXCELLENT ⭐⭐⭐⭐⭐';
  if (score >= 80) return 'VERY GOOD ⭐⭐⭐⭐';
  if (score >= 70) return 'GOOD ⭐⭐⭐';
  if (score >= 60) return 'FAIR ⭐⭐';
  if (score >= 50) return 'NEEDS IMPROVEMENT ⭐';
  return 'CRITICAL ⚠️';
}

function generateRecommendations(p50, p95, p99, rps, errorRate, successRate) {
  const recs = [];
  
  if (p50 > 100) recs.push('🔴 HIGH: Median latency >100ms - optimize database queries, add caching');
  else if (p50 > 50) recs.push('🟡 MEDIUM: Median latency >50ms - review hot paths');
  
  if (p95 > 500) recs.push('🔴 HIGH: p95 latency >500ms - investigate tail latency causes');
  else if (p95 > 200) recs.push('🟡 MEDIUM: p95 latency >200ms - add request queuing');
  
  if (p99 > 1000) recs.push('🔴 HIGH: p99 latency >1s - circuit breakers needed');
  
  if (rps < 50) recs.push('🔴 HIGH: Throughput <50 RPS - scale horizontally, optimize DB');
  else if (rps < 100) recs.push('🟡 MEDIUM: Throughput <100 RPS - consider connection pooling');
  
  if (errorRate > 5) recs.push('🔴 CRITICAL: Error rate >5% - investigate immediately');
  else if (errorRate > 1) recs.push('🟡 MEDIUM: Error rate >1% - add retries, improve error handling');
  
  if (successRate < 99) recs.push('🟡 MEDIUM: Success rate <99% - improve reliability');
  
  if (recs.length === 0) {
    recs.push('🟢 EXCELLENT: All metrics within optimal ranges');
    recs.push('💡 Consider: Load testing at 2x capacity for headroom validation');
  }
  
  recs.forEach((r, i) => console.log(`${i + 1}. ${r}`));
}

// Main
const args = process.argv.slice(2);
if (args.length === 0) {
  console.log('Usage: node analyze-results.js <results-file.json>');
  console.log('Example: node analyze-results.js k6-results.json');
  process.exit(1);
}

analyzeResults(args[0]);