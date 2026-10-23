import psycopg2, os
from dotenv import load_dotenv

load_dotenv('.env')
conn = psycopg2.connect(os.environ.get('DATABASE_URL'))
conn.autocommit = True
cur = conn.cursor()

print("=" * 70)
print("SMARTIFY — REAL DEMO L1 -> L2 FORWARDING VALIDATION")
print("=" * 70)

# Fetch user accounts
cur.execute("SELECT id, full_name, email, role, department_id, authority_level_id FROM profiles WHERE email IN ('mba.faculty@campus.edu', 'mba.hod@campus.edu', 'warden.demo@campus.edu');")
users = {r[2]: {'id': r[0], 'name': r[1], 'dept_id': r[4], 'level_id': r[5]} for r in cur.fetchall()}
faculty = users['mba.faculty@campus.edu']
hod = users['mba.hod@campus.edu']
warden = users['warden.demo@campus.edu']

print(f"Loaded Faculty (L1): {faculty['name']} ({faculty['id']})")
print(f"Loaded HoD (L2): {hod['name']} ({hod['id']})")
print(f"Loaded Warden (Hostel L1): {warden['name']} ({warden['id']})")

# ------------------------------------------------------------------------------
# STEP 1: Verify Initial State of SMT-2026-01028
# ------------------------------------------------------------------------------
print("\n>>> STEP 1: Verifying Initial State of SMT-2026-01028")
cur.execute("""
SELECT c.id, c.tracking_number, c.status, al.level_number, d.name
FROM complaints c
JOIN authority_levels al ON c.current_authority_level_id = al.id
JOIN departments d ON c.department_id = d.id
WHERE c.tracking_number = 'SMT-2026-01028';
""")
c_row = cur.fetchone()
print(f"  Grievance: {c_row[1]} | Status: {c_row[2]} | Level: {c_row[3]} | Dept: {c_row[4]}")
complaint_id = c_row[0]

assert c_row[2] == 'PENDING', f"Expected PENDING, got {c_row[2]}"
assert c_row[3] == 1, f"Expected Level 1, got {c_row[3]}"
assert c_row[4] == 'Department of MBA', f"Expected Department of MBA, got {c_row[4]}"

# ------------------------------------------------------------------------------
# STEP 2: Execute Forwarding as MBA L1 (Dr. Amit Trivedi)
# ------------------------------------------------------------------------------
print("\n>>> STEP 2: Executing Forwarding RPC as MBA L1 (Dr. Amit Trivedi)")
# Simulate authenticated Supabase session
cur.execute("SELECT set_config('request.jwt.claim.sub', %s, false);", (str(faculty['id']),))

reason = 'Referred to Head of Department for syllabus coverage review and faculty coordination.'
cur.execute("SELECT public.forward_grievance_to_next_tier(%s, %s);", (complaint_id, reason))
rpc_res = cur.fetchone()[0]

print("  RPC Result:")
for k, v in rpc_res.items():
    print(f"    {k}: {v}")

assert rpc_res['success'] is True, "RPC success must be True"
assert rpc_res['to_level_number'] == 2, f"Expected to_level_number 2, got {rpc_res['to_level_number']}"
assert str(rpc_res['assigned_authority_id']) == str(hod['id']), "Assigned authority must match Dr. Neha Gupta"
assert 'Neha Gupta' in rpc_res['assigned_authority_name'], "Assigned name must be Dr. Neha Gupta"

# ------------------------------------------------------------------------------
# STEP 3: Verify Complaint Record in Database
# ------------------------------------------------------------------------------
print("\n>>> STEP 3: Verifying Database Complaint Row Post-Forwarding")
cur.execute("""
SELECT c.tracking_number, c.status, al.level_number, al.title,
       c.assigned_authority_id, p.full_name as assigned_name, d.name as dept_name
FROM complaints c
JOIN authority_levels al ON c.current_authority_level_id = al.id
JOIN profiles p ON c.assigned_authority_id = p.id
JOIN departments d ON c.department_id = d.id
WHERE c.id = %s;
""", (complaint_id,))
updated_c = cur.fetchone()
print(f"  Tracking: {updated_c[0]}")
print(f"  Status: {updated_c[1]}")
print(f"  Current Level: Level {updated_c[2]} ({updated_c[3]})")
print(f"  Assigned Authority: {updated_c[5]} (ID: {updated_c[4]})")
print(f"  Department: {updated_c[6]}")

assert updated_c[1] == 'ESCALATED', f"Status must be ESCALATED, got {updated_c[1]}"
assert updated_c[2] == 2, f"Level must be 2, got {updated_c[2]}"
assert str(updated_c[4]) == str(hod['id']), f"Assigned authority must be Dr. Neha Gupta"
assert updated_c[6] == 'Department of MBA', "Department must remain Department of MBA"

# ------------------------------------------------------------------------------
# STEP 4: Verify Timeline & Status History
# ------------------------------------------------------------------------------
print("\n>>> STEP 4: Verifying Timeline & Actor Audit Trail")
cur.execute("""
SELECT h.event_type, h.new_status, h.actor_display_name, h.actor_role,
       h.actor_designation, h.assigned_to_tier, h.assigned_to_name, h.remarks, h.created_at
FROM complaint_status_history h
WHERE h.complaint_id = %s
ORDER BY h.created_at ASC;
""", (complaint_id,))
history = cur.fetchall()
for idx, h in enumerate(history, 1):
    print(f"  {idx}. [{h[0]}] Status: {h[1]}")
    print(f"     Actor: {h[2]} ({h[3]}) — {h[4]}")
    print(f"     Assigned to: {h[5]} — {h[6]}")
    print(f"     Remarks: {h[7]}")

fwd_event = [h for h in history if h[0] == 'FORWARDED'][-1]
assert 'Amit Trivedi' in fwd_event[2], f"Forwarding actor must be Dr. Amit Trivedi, got {fwd_event[2]}"
assert 'Dr. Neha Gupta' in str(fwd_event[6]), f"Assigned name in history must be Dr. Neha Gupta, got {fwd_event[6]}"
assert 'Head of Department' in str(fwd_event[5]), f"Assigned tier must be Head of Department, got {fwd_event[5]}"

# ------------------------------------------------------------------------------
# STEP 5: Verify Visibility in Dr. Neha Gupta (MBA HoD) Queue Under RLS
# ------------------------------------------------------------------------------
print("\n>>> STEP 5: Verifying Visibility in Dr. Neha Gupta (MBA HoD) Queue")
cur.execute("SELECT set_config('request.jwt.claim.sub', %s, false);", (str(hod['id']),))
cur.execute("SET ROLE authenticated;")
cur.execute("""
SELECT c.id, c.tracking_number, c.title, c.status,
       d.name as dept_name, al.title as level_title,
       p_auth.full_name as assigned_authority
FROM complaints c
LEFT JOIN departments d ON c.department_id = d.id
LEFT JOIN authority_levels al ON c.current_authority_level_id = al.id
LEFT JOIN profiles p_auth ON c.assigned_authority_id = p_auth.id
WHERE c.tracking_number = 'SMT-2026-01028';
""")
hod_queue_items = cur.fetchall()
cur.execute("RESET ROLE;")
print(f"  Found {len(hod_queue_items)} row(s) in Dr. Neha Gupta's queue:")
for row in hod_queue_items:
    print(f"    Grievance: {row[1]} | Status: {row[3]} | Level: {row[5]} | Assigned: {row[6]}")

assert len(hod_queue_items) == 1, "SMT-2026-01028 MUST be visible in Dr. Neha Gupta's queue"
assert hod_queue_items[0][6] == 'Dr. Neha Gupta', "Assigned authority must be Dr. Neha Gupta"

# ------------------------------------------------------------------------------
# STEP 6: Negative Case Validation (Hostel Warden Forwarding with No Level 2)
# ------------------------------------------------------------------------------
print("\n>>> STEP 6: Negative Case Validation (Hostel L1 Forwarding with No Level 2)")
# Create a fresh PENDING hostel complaint
cur.execute("SELECT id FROM departments WHERE code = 'HOSTEL';")
h_dept_id = cur.fetchone()[0]
cur.execute("SELECT id FROM authority_levels WHERE level_number = 1;")
lvl1_id = cur.fetchone()[0]
cur.execute("SELECT id FROM profiles WHERE role = 'student' LIMIT 1;")
st_id = cur.fetchone()[0]
cur.execute("""
INSERT INTO complaints (student_id, department_id, current_authority_level_id, title, description, category, incident_date, status)
VALUES (%s, %s, %s, 'Hostel Room Repair Test', 'Window latch is broken in hostel room 302 and needs urgent maintenance replacement.', 'Hostel Facilities', CURRENT_DATE, 'PENDING')
RETURNING id, tracking_number;
""", (st_id, h_dept_id, lvl1_id))
hostel_test_id, hostel_test_tracking = cur.fetchone()

# Act as Hostel Warden
cur.execute("SELECT set_config('request.jwt.claim.sub', %s, false);", (str(warden['id']),))
caught_expected_error = False
try:
    cur.execute("SELECT public.forward_grievance_to_next_tier(%s, %s);", (hostel_test_id, 'Forwarding to Level 2.'))
except Exception as e:
    err_str = str(e)
    print(f"  Controlled error received: {err_str.strip()}")
    assert "No active Level 2 authority configured for Hostel & Residential Life" in err_str, f"Unexpected error: {err_str}"
    assert "PGRST116" not in err_str, "Must NOT produce PGRST116"
    caught_expected_error = True

assert caught_expected_error is True, "Negative test MUST raise controlled exception"
print("  Negative test PASSED with clean controlled application error!")

print("\n" + "=" * 70)
print("ALL REAL DEMO FORWARDING TESTS PASSED WITH 100% SUCCESS!")
print("=" * 70)
