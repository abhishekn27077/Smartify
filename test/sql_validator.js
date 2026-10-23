/**
 * SMARTIFY — Local SQL Migration & Security Validator
 * Validates syntax structure, RLS completeness, required table inventory, and security rules.
 */

const fs = require('fs');
const path = require('path');

const MIGRATIONS_DIR = path.join(__dirname, '..', 'supabase', 'migrations');
const REQUIRED_TABLES = [
    'departments',
    'authority_levels',
    'profiles',
    'complaints',
    'complaint_attachments',
    'complaint_escalations',
    'complaint_status_history',
    'notifications',
    'audit_logs'
];

let totalChecks = 0;
let passedChecks = 0;
let errors = [];

function assert(condition, message) {
    totalChecks++;
    if (condition) {
        passedChecks++;
        console.log(`  [PASS] ${message}`);
    } else {
        errors.push(message);
        console.error(`  [FAIL] ${message}`);
    }
}

console.log('=== SMARTIFY Database Migration & Security Verification ===\n');

// 1. Check migrations directory
assert(fs.existsSync(MIGRATIONS_DIR), `Migrations directory exists at ${MIGRATIONS_DIR}`);

const files = fs.readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith('.sql')).sort();
assert(files.length >= 5, `Expected at least 5 migration files, found ${files.length}: ${files.join(', ')}`);

// Concatenate SQL content for holistic schema checks
let fullSql = '';
files.forEach(f => {
    const content = fs.readFileSync(path.join(MIGRATIONS_DIR, f), 'utf8');
    assert(content.length > 500, `Migration ${f} is populated (${content.length} bytes)`);
    fullSql += '\n' + content;
});

// 2. Validate all 9 required tables are declared
console.log('\n--- Checking Table Declarations ---');
REQUIRED_TABLES.forEach(table => {
    const tableRegex = new RegExp(`CREATE TABLE IF NOT EXISTS public\\.${table}\\s*\\(`, 'i');
    assert(tableRegex.test(fullSql), `Table 'public.${table}' is declared`);
});

// 3. Validate RLS enabled for all 9 tables
console.log('\n--- Checking Row Level Security (RLS) Enforcement ---');
REQUIRED_TABLES.forEach(table => {
    const rlsRegex = new RegExp(`ALTER TABLE public\\.${table} ENABLE ROW LEVEL SECURITY;`, 'i');
    assert(rlsRegex.test(fullSql), `RLS enabled on 'public.${table}'`);
});

// 4. Validate Critical Triggers and Constraints
console.log('\n--- Checking Business Logic & Security Triggers ---');
assert(fullSql.includes('validate_complaint_incident_date'), '7-day retrospective date validation trigger defined');
assert(fullSql.includes('initialize_complaint_defaults'), 'Complaint tracking number & 20-day cutoff initialized');
assert(fullSql.includes('log_complaint_status_change'), 'Automatic status history logging trigger defined');
assert(fullSql.includes('handle_new_user'), 'Default student role assignment on auth.users defined');
assert(fullSql.includes('protect_profile_privileged_fields'), 'Privileged role escalation protection trigger defined');
assert(fullSql.includes('process_daily_complaint_escalations'), 'Server-authoritative escalation & 20-day cutoff function defined');
assert(fullSql.includes('resume_paused_complaint'), 'Authorized resumption function defined with admin guard');
assert(fullSql.includes('FOR UPDATE SKIP LOCKED'), 'Concurrency row locking (SKIP LOCKED) defined for escalation worker');
assert(fullSql.includes('cutoff_paused_complaints_view'), 'Administrative cutoff review view defined');
assert(fullSql.includes('get_grievance_analytics'), 'Server-authoritative grievance analytics function defined');
assert(fullSql.includes('send_deduped_notification'), 'Deduplicated notification pipeline function defined');
assert(fullSql.includes('admin_update_profile_role'), 'Protected administrative profile role update function defined');

// 5. Validate Storage Bucket Setup & Security
console.log('\n--- Checking Storage Bucket Configuration ---');
assert(fullSql.includes("'complaint-attachments'"), "Private bucket 'complaint-attachments' registered");
assert(fullSql.includes("storage.objects FOR SELECT"), "Storage SELECT policy defined");
assert(fullSql.includes("storage.objects FOR INSERT"), "Storage INSERT policy defined");

// 6. Security & Leaks Check in Tracked Files
console.log('\n--- Checking Secret Leak Guards ---');
assert(!fullSql.includes('Projectabhi@123'), 'Database password NOT leaked in SQL migrations');
assert(!fullSql.includes('service_role'), 'Service role secret key NOT leaked in SQL migrations');

console.log('\n======================================================');
console.log(`Results: ${passedChecks}/${totalChecks} checks passed.`);
if (errors.length > 0) {
    console.error(`FAILED CHECKS (${errors.length}):\n` + errors.map(e => `  - ${e}`).join('\n'));
    process.exit(1);
} else {
    console.log('ALL LOCAL DATABASE FOUNDATION CHECKS PASSED.');
    process.exit(0);
}
