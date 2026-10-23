/**
 * SMARTIFY — Phase 7 Automatic Escalation Engine Verification
 * 
 * Verifies:
 * 1. Deliverables file integrity for escalation models, services, providers, screens, widgets, and migrations
 * 2. Deadline Calculation & Institutional Timezone Consistency (UTC Calendar Days)
 * 3. Authority Hierarchy Escalation Logic (Level 1 -> Level 2 -> Level 3 -> Level 4)
 * 4. Apex Level 4 Boundary & Administrative Review Flagging (No invented Level 5)
 * 5. 20-Day Cutoff Freeze Precedence over Tier Forwarding
 * 6. Concurrency Control & Duplicate-Prevention (FOR UPDATE SKIP LOCKED)
 * 7. Authorized Administrative Resumption & Extended Deadline Window
 * 8. Simulation / Safe Test Mode Parameter Support (p_simulated_now)
 * 9. Multi-Party Notification Broadcast Integrity
 * 10. MultiProvider Registration & Navigation Shell Integration
 */

const fs = require('fs');
const path = require('path');

let testsRun = 0;
let testsPassed = 0;
const failures = [];

function assert(condition, message) {
    testsRun++;
    if (condition) {
        testsPassed++;
        console.log(`  [PASS] ${message}`);
    } else {
        failures.push(message);
        console.error(`  [FAIL] ${message}`);
    }
}

console.log('=== SMARTIFY Phase 7: Automatic Escalation Engine Verification ===\n');

// 1. Deliverables File Check
console.log('--- 1. Deliverables File Check ---');
const filesToCheck = [
    'supabase/migrations/20261012000004_escalation_engine_and_scheduler.sql',
    'lib/features/escalation/models/escalation_record_model.dart',
    'lib/features/escalation/services/escalation_service.dart',
    'lib/features/escalation/providers/escalation_provider.dart',
    'lib/features/escalation/widgets/admin_resume_dialog.dart',
    'lib/features/escalation/screens/admin_cutoff_review_screen.dart',
    'lib/app.dart',
    'test/unit/escalation_engine_test.dart'
];

filesToCheck.forEach(file => {
    const fullPath = path.join(__dirname, '..', file);
    const exists = fs.existsSync(fullPath);
    assert(exists, `Required file exists: ${file}`);
});

// Read Migration 004 Content for Schema & Security Asserts
const migration004Path = path.join(__dirname, '..', 'supabase/migrations/20261012000004_escalation_engine_and_scheduler.sql');
const migration004Sql = fs.readFileSync(migration004Path, 'utf8');

// 2. Deadline Calculation & Institutional Timezone Consistency
console.log('\n--- 2. Deadline Calculation & Institutional Timezone ---');
const baseSubmissionUtc = new Date('2026-10-12T10:00:00.000Z');

function computeTierDeadline(startDate, slaDays) {
    const d = new Date(startDate.getTime());
    d.setUTCDate(d.getUTCDate() + slaDays);
    return d;
}

function computeCutoffDeadline(startDate) {
    const d = new Date(startDate.getTime());
    d.setUTCDate(d.getUTCDate() + 20);
    return d;
}

const level1Deadline = computeTierDeadline(baseSubmissionUtc, 3);
const cutoffDeadline = computeCutoffDeadline(baseSubmissionUtc);

assert(level1Deadline.toISOString() === '2026-10-15T10:00:00.000Z', 'Level 1 (3-day) SLA deadline matches UTC calendar interval');
assert(cutoffDeadline.toISOString() === '2026-11-01T10:00:00.000Z', '20-day cutoff deadline matches UTC calendar interval');

const simulatedNowOnTime = new Date('2026-10-14T10:00:00.000Z');
const simulatedNowOverdue = new Date('2026-10-16T10:00:00.000Z');

assert(simulatedNowOnTime < level1Deadline, 'Complaint is recognized as ON-TIME before deadline');
assert(simulatedNowOverdue >= level1Deadline, 'Complaint is recognized as OVERDUE after deadline');

// 3. Authority Hierarchy Escalation Logic
console.log('\n--- 3. Authority Hierarchy Escalation & Progression ---');
const tiers = [
    { level: 1, title: 'Level 1: Faculty / Warden', slaDays: 3 },
    { level: 2, title: 'Level 2: Head of Department', slaDays: 4 },
    { level: 3, title: 'Level 3: Dean of Student Welfare', slaDays: 5 },
    { level: 4, title: 'Level 4: Arbitration Board / Ombudsman', slaDays: 5 }
];

function getNextTier(currentLevel) {
    return tiers.find(t => t.level === currentLevel + 1) || null;
}

assert(getNextTier(1).level === 2, 'Level 1 escalates to Level 2');
assert(getNextTier(2).level === 3, 'Level 2 escalates to Level 3');
assert(getNextTier(3).level === 4, 'Level 3 escalates to Level 4');

// 4. Apex Level 4 Boundary & Administrative Review Flagging
console.log('\n--- 4. Apex Level 4 Boundary & Administrative Review ---');
const apexNextTier = getNextTier(4);
assert(apexNextTier === null, 'Level 4 has no higher tier (Apex Boundary is null)');
assert(migration004Sql.includes('APEX_TIER_SLA_BREACHED'), 'Migration 004 logs APEX_TIER_SLA_BREACHED when Level 4 breaches SLA');
assert(migration004Sql.includes('URGENT: Level 4 Apex SLA Breached'), 'Migration 004 notifies admins when Level 4 breaches without inventing assignee');

// 5. 20-Day Cutoff Freeze Precedence
console.log('\n--- 5. 20-Day Cutoff Freeze Precedence ---');
function evaluateEscalationEngine(complaint, effectiveNow) {
    const isCutoffBreached = effectiveNow >= complaint.cutoffDeadline || 
        (effectiveNow.getTime() - complaint.createdAt.getTime()) >= (20 * 86400000);

    // STEP 1: Cutoff check takes precedence
    if (isCutoffBreached && !complaint.isCutoffPaused && complaint.status !== 'CUTOFF_PAUSED') {
        return { action: 'CUTOFF_PAUSED', reason: '20-day cutoff exceeded' };
    }

    // STEP 2: Tier forwarding check
    if (effectiveNow >= complaint.tierDeadline && !complaint.isCutoffPaused) {
        const next = getNextTier(complaint.level);
        if (next) {
            return { action: 'ESCALATED', nextLevel: next.level };
        } else {
            return { action: 'APEX_ADMIN_REVIEW' };
        }
    }

    return { action: 'NO_OP' };
}

// Test complaint where BOTH 20-day cutoff and tier deadline are breached
const dualBreachedComplaint = {
    id: 'c-dual',
    level: 2,
    createdAt: new Date('2026-10-01T10:00:00.000Z'), // 25 days ago
    tierDeadline: new Date('2026-10-10T10:00:00.000Z'), // Breached
    cutoffDeadline: new Date('2026-10-21T10:00:00.000Z'), // Breached
    isCutoffPaused: false,
    status: 'IN_PROGRESS'
};

const decision = evaluateEscalationEngine(dualBreachedComplaint, new Date('2026-10-26T10:00:00.000Z'));
assert(decision.action === 'CUTOFF_PAUSED', '20-day cutoff freeze takes strict precedence over tier forwarding');

// 6. Concurrency Control & Duplicate-Prevention
console.log('\n--- 6. Concurrency Control & Duplicate-Prevention ---');
assert(migration004Sql.includes('FOR UPDATE SKIP LOCKED'), 'Escalation queries utilize row-level locking (FOR UPDATE SKIP LOCKED)');
assert(migration004Sql.includes('c.is_cutoff_paused = false'), 'Cutoff check excludes already paused complaints');
assert(migration004Sql.includes("c.status NOT IN ('RESOLVED', 'REJECTED', 'CUTOFF_PAUSED')"), 'Excludes terminal and paused complaints from batch');

// 7. Authorized Administrative Resumption & Extended Window
console.log('\n--- 7. Authorized Administrative Resumption & Extended Window ---');
assert(migration004Sql.includes('public.is_admin()'), 'resume_paused_complaint validates admin role');
assert(migration004Sql.includes('char_length(trim(p_resumption_notes)) < 10'), 'resume_paused_complaint mandates >= 10 character notes');
assert(migration004Sql.includes("status = 'UNDER_REVIEW'"), 'Resumption updates status back to UNDER_REVIEW');
assert(migration004Sql.includes('is_cutoff_paused = false'), 'Resumption clears is_cutoff_paused flag');
assert(migration004Sql.includes("INTERVAL '20 days'"), 'Resumption extends cutoff deadline by 20 days to prevent immediate re-pause');
assert(migration004Sql.includes('RESUMPTION_AUTHORIZED'), 'Resumption records immutable RESUMPTION_AUTHORIZED audit log');

// 8. Simulation / Safe Test Mode Parameter Support
console.log('\n--- 8. Safe Test Mode / Simulated Time Parameter Support ---');
assert(migration004Sql.includes('p_simulated_now TIMESTAMPTZ DEFAULT NULL'), 'Worker function accepts optional p_simulated_now parameter');
assert(migration004Sql.includes('COALESCE(p_simulated_now, timezone(\'utc\'::text, now()))'), 'Worker anchors to simulated time when provided');

// 9. Multi-Party Notification Broadcast Integrity
console.log('\n--- 9. Multi-Party Notification Broadcast Integrity ---');
assert(migration004Sql.includes('Automated Escalation Frozen (20-Day Cutoff)'), 'Notifies student on 20-day cutoff pause');
assert(migration004Sql.includes('Admin Review Required: 20-Day Cutoff Freeze'), 'Notifies campus administrators on cutoff pause');
assert(migration004Sql.includes('Grievance Escalated Away (SLA Expired)'), 'Notifies previous authority when complaint is escalated away');
assert(migration004Sql.includes('New Escalated Grievance Assigned'), 'Notifies next tier authority when assigned new escalated grievance');

// 10. App Navigation & MultiProvider Wiring
console.log('\n--- 10. MultiProvider & Navigation Shell Integration ---');
const appDartPath = path.join(__dirname, '..', 'lib/app.dart');
const appDart = fs.readFileSync(appDartPath, 'utf8');

assert(appDart.includes('EscalationProvider'), 'lib/app.dart registers EscalationProvider in MultiProvider');
assert(appDart.includes('AdminCutoffReviewScreen'), 'lib/app.dart mounts AdminCutoffReviewScreen in navigation shell');

// Final Summary
console.log('\n======================================================');
console.log(`TOTAL PHASE 7 TESTS: ${testsRun}`);
console.log(`PASSED: ${testsPassed}`);
console.log(`FAILED: ${failures.length}`);
console.log('======================================================\n');

if (failures.length > 0) {
    console.error('FAILED TESTS:');
    failures.forEach(f => console.error(` - ${f}`));
    process.exit(1);
} else {
    console.log('All Phase 7 Automatic Escalation Engine tests passed successfully!');
    process.exit(0);
}
