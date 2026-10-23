const fs = require('fs');
const https = require('https');

console.log('=== SUPABASE BACKEND READ-ONLY CONNECTION AUDIT ===\n');

// Load .env
const envContent = fs.readFileSync('.env', 'utf8');
const env = {};
envContent.split('\n').forEach(line => {
  const parts = line.split('=');
  if (parts.length >= 2 && parts[0].trim()) {
    env[parts[0].trim()] = parts.slice(1).join('=').trim();
  }
});

const url = env.SUPABASE_URL;
const anonKey = env.SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  console.log('Error: SUPABASE_URL or SUPABASE_ANON_KEY missing in .env');
  process.exit(1);
}

const urlHost = new URL(url).hostname;
console.log(`Connecting to Supabase host: ${urlHost}`);
console.log(`Anon Key present: ${anonKey ? 'Yes (length ' + anonKey.length + ')' : 'No'}`);

// Test 1: Auth settings endpoint
function checkEndpoint(endpointPath, headers, label) {
  return new Promise((resolve) => {
    const options = {
      hostname: urlHost,
      port: 443,
      path: endpointPath,
      method: 'GET',
      headers: {
        'apikey': anonKey,
        'Authorization': `Bearer ${anonKey}`,
        ...headers
      },
      timeout: 10000
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        resolve({
          label,
          statusCode: res.statusCode,
          statusMessage: res.statusMessage,
          bodySnippet: data.substring(0, 200)
        });
      });
    });

    req.on('error', (e) => {
      resolve({
        label,
        statusCode: 0,
        error: e.message
      });
    });

    req.on('timeout', () => {
      req.destroy();
      resolve({
        label,
        statusCode: 0,
        error: 'Connection timed out'
      });
    });

    req.end();
  });
}

async function runAudit() {
  // Test Auth Health
  const authRes = await checkEndpoint('/auth/v1/settings', {}, 'Auth Service (/auth/v1/settings)');
  console.log(`[${authRes.statusCode === 200 ? 'PASS' : 'STATUS ' + authRes.statusCode}] ${authRes.label}`);
  if (authRes.error) console.log(`  Error: ${authRes.error}`);
  else console.log(`  Response: HTTP ${authRes.statusCode} (${authRes.bodySnippet.substring(0, 100)}...)`);

  // Test REST Root
  const restRoot = await checkEndpoint('/rest/v1/', {}, 'REST Gateway (/rest/v1/)');
  console.log(`[STATUS ${restRoot.statusCode}] ${restRoot.label}`);
  if (restRoot.error) console.log(`  Error: ${restRoot.error}`);
  else console.log(`  Response: HTTP ${restRoot.statusCode}`);

  // Test Public Read on Categories (read-only)
  const catRes = await checkEndpoint('/rest/v1/complaint_categories?select=*', {}, 'Table: complaint_categories');
  console.log(`[STATUS ${catRes.statusCode}] ${catRes.label}`);
  if (catRes.error) console.log(`  Error: ${catRes.error}`);
  else {
    console.log(`  Response: HTTP ${catRes.statusCode} (${catRes.bodySnippet.substring(0, 100)}...)`);
  }

  // Test Public Read on Departments (read-only)
  const deptRes = await checkEndpoint('/rest/v1/departments?select=*', {}, 'Table: departments');
  console.log(`[STATUS ${deptRes.statusCode}] ${deptRes.label}`);
  if (deptRes.error) console.log(`  Error: ${deptRes.error}`);
  else {
    console.log(`  Response: HTTP ${deptRes.statusCode} (${deptRes.bodySnippet.substring(0, 100)}...)`);
  }

  // Test Grievances read with Anon Key (should enforce RLS / return [] or 401 unauthenticated)
  const grvRes = await checkEndpoint('/rest/v1/grievances?select=*', {}, 'Table: grievances (Anon Key RLS Test)');
  console.log(`[STATUS ${grvRes.statusCode}] ${grvRes.label}`);
  if (grvRes.error) console.log(`  Error: ${grvRes.error}`);
  else {
    console.log(`  Response: HTTP ${grvRes.statusCode} (${grvRes.bodySnippet.substring(0, 100)}...)`);
  }
}

runAudit();
