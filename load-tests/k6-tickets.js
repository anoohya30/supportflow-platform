// Load test for the SupportFlow API (acceptance target 2.1):
//   10 minutes at a steady 20 requests/second against 2 replicas,
//   pass if p95 latency < 500 ms and server errors (5xx) < 1%.
//
// Run from the laptop with Docker (no install needed):
//   docker run --rm -i -u "$(id -u):$(id -g)" -e BASE_URL=https://staging.<ip-with-dashes>.sslip.io \
//     -v "$PWD/docs/evidence:/out" grafana/k6:1.8.1 run --quiet \
//     --summary-export=/out/day10-k6-summary.json - < load-tests/k6-tickets.js
//
// Traffic mix required by the brief: 80% reads and 20% creates
//   reads   = 50% list tickets + 30% read one ticket
//   creates = 20% create a ticket
// Only synthetic data is created. Expected validation errors (HTTP 4xx) are
// counted separately in "validation_errors" and are NOT server errors.
import http from 'k6/http';
import { check } from 'k6';
import { Counter, Rate } from 'k6/metrics';

const BASE = __ENV.BASE_URL || 'http://localhost:8000';
const serverErrors = new Rate('server_errors'); // share of responses with status >= 500
const validationErrors = new Counter('validation_errors'); // 4xx responses, reported separately
const reads = new Counter('mix_reads');
const creates = new Counter('mix_creates');

export const options = {
  scenarios: {
    steady_20_rps: {
      executor: 'constant-arrival-rate', // keeps 20 req/s even if responses slow down
      rate: 20,
      timeUnit: '1s',
      duration: __ENV.DURATION || '10m',
      preAllocatedVUs: 20,
      maxVUs: 60,
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<500'], // target: p95 < 500 ms
    server_errors: ['rate<0.01'], // target: 5xx < 1%
    checks: ['rate>0.99'],
    dropped_iterations: ['count<60'], // could not keep the 20 req/s rate
  },
  summaryTrendStats: ['avg', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

const jsonParams = (name) => ({ headers: { 'Content-Type': 'application/json' }, tags: { name: name } });
const PRIORITIES = ['low', 'normal', 'high'];
const pick = (list) => list[Math.floor(Math.random() * list.length)];
const seededId = () => 1 + Math.floor(Math.random() * 1000); // ids 1..1000 exist (seed)

export default function () {
  const r = Math.random();
  let res;
  if (r < 0.5) {
    const offset = Math.floor(Math.random() * 900);
    res = http.get(`${BASE}/tickets?limit=20&offset=${offset}`, { tags: { name: 'GET /tickets' } });
    check(res, { 'list 200': (x) => x.status === 200 });
    reads.add(1);
  } else if (r < 0.8) {
    res = http.get(`${BASE}/tickets/${seededId()}`, { tags: { name: 'GET /tickets/{id}' } });
    check(res, { 'read 200': (x) => x.status === 200 });
    reads.add(1);
  } else {
    const body = JSON.stringify({
      subject: `Load test ticket ${__VU}-${__ITER}`,
      description: 'Synthetic ticket created by the k6 load test. No real customer data.',
      priority: pick(PRIORITIES),
    });
    res = http.post(`${BASE}/tickets`, body, jsonParams('POST /tickets'));
    check(res, { 'create 201': (x) => x.status === 201 });
    creates.add(1);
  }
  serverErrors.add(res.status >= 500);
  if (res.status >= 400 && res.status < 500) validationErrors.add(1);
}
