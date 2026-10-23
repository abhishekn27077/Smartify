import os
import psycopg2
from dotenv import load_dotenv

load_dotenv('.env')
url = os.environ.get('DATABASE_URL')
conn = psycopg2.connect(url)
conn.autocommit = True
cur = conn.cursor()

print("=" * 60)
print("SMARTIFY — REAL DEMO FLOW VALIDATION (MBA REDRESSAL)")
print("=" * 60)

# Fetch user IDs
cur.execute("SELECT id, full_name, email FROM profiles WHERE email IN ('mba.student@campus.edu', 'mba.faculty@campus.edu', 'mba.hod@campus.edu', 'mba.dean@campus.edu');")
users = {r[2]: {'id': r[0], 'name': r[1]} for r in cur.fetchall()}
print(f"Loaded demo accounts: {users}")

student = users['mba.student@campus.edu']
faculty = users['mba.faculty@campus.edu']
hod = users['mba.hod@campus.edu']

# Fetch MBA department ID
cur.execute("SELECT id FROM departments WHERE code = 'MBA';")
mba_dept_id = cur.fetchone()[0]

# Fetch L1 & L2 authority level IDs
cur.execute("SELECT id, level_number, title FROM authority_levels ORDER BY level_number;")
levels = {r[1]: {'id': r[0], 'title': r[2]} for r in cur.fetchall()}

# ==============================================================================
# FLOW 1: Student Submits -> L1 Reviews -> L1 Resolves
# ==============================================================================
print("\n>>> TESTING FLOW 1: Student Submits -> L1 Reviews -> L1 Resolves")

def set_acting_user(user_id):
    cur.execute("SELECT set_config('request.jwt.claim.sub', %s, false);", (str(user_id),))

# 1. Student submits complaint
set_acting_user(student['id'])
cur.execute('''
INSERT INTO public.complaints (
    student_id, department_id, current_authority_level_id,
    title, description, category, incident_date, status
) VALUES (
    %s, %s, %s,
    'MBA Internal Assessment Review Request',
    'Requesting re-evaluation of Mid-Term internal assessment components.',
    'Academic Affairs (Evaluation & Grading)',
    CURRENT_DATE,
    'PENDING'
) RETURNING id, tracking_number;
''', (student['id'], mba_dept_id, levels[1]['id']))
flow1_id, flow1_tracking = cur.fetchone()
print(f"[Flow 1] Grievance submitted: {flow1_tracking} (ID: {flow1_id})")

# 2. MBA L1 Faculty marks UNDER_REVIEW
set_acting_user(faculty['id'])
cur.execute('''
UPDATE public.complaints
SET status = 'UNDER_REVIEW',
    assigned_authority_id = %s,
    status_remarks = 'Reviewing internal assessment component sheets with student records.',
    updated_at = timezone('utc'::text, now())
WHERE id = %s;
''', (faculty['id'], flow1_id))
print(f"[Flow 1] L1 Dr. Amit Trivedi marked UNDER_REVIEW")

# 3. MBA L1 Faculty marks RESOLVED
set_acting_user(faculty['id'])
cur.execute('''
UPDATE public.complaints
SET status = 'RESOLVED',
    resolution_notes = 'Internal assessment component marks verified and updated on ERP portal.',
    resolved_at = timezone('utc'::text, now()),
    updated_at = timezone('utc'::text, now())
WHERE id = %s;
''', (flow1_id,))
print(f"[Flow 1] L1 Dr. Amit Trivedi marked RESOLVED")

# Verify Timeline for Flow 1
cur.execute('''
SELECT h.event_type, h.new_status, h.actor_display_name, h.actor_role,
       h.actor_designation, h.actor_department_name, h.remarks, h.created_at
FROM complaint_status_history h
WHERE h.complaint_id = %s
ORDER BY h.created_at ASC;
''', (flow1_id,))
flow1_history = cur.fetchall()

print(f"\n[Flow 1 Timeline Results] Total Events: {len(flow1_history)}")
for idx, h in enumerate(flow1_history, 1):
    print(f"  {idx}. [{h[0]}] Status: {h[1]}")
    print(f"     Actor: {h[2]} ({h[3]})")
    print(f"     Designation: {h[4]}")
    print(f"     Department: {h[5]}")
    print(f"     Remarks: {h[6]}")

# Assertions for Flow 1
assert len(flow1_history) == 3, f"Expected exactly 3 timeline events, found {len(flow1_history)}"
assert flow1_history[0][0] == 'SUBMITTED', f"Event 1 must be SUBMITTED, got {flow1_history[0][0]}"
assert 'Rohan Verma' in flow1_history[0][2], f"Event 1 actor must be Rohan Verma, got {flow1_history[0][2]}"
assert flow1_history[0][3] == 'student', f"Event 1 role must be student, got {flow1_history[0][3]}"
assert flow1_history[0][4] == 'MBA Student', f"Event 1 designation must be MBA Student, got {flow1_history[0][4]}"

assert flow1_history[1][0] == 'UNDER_REVIEW', f"Event 2 must be UNDER_REVIEW, got {flow1_history[1][0]}"
assert 'Amit Trivedi' in flow1_history[1][2], f"Event 2 actor must be Dr. Amit Trivedi, got {flow1_history[1][2]}"
assert flow1_history[1][3] == 'authority', f"Event 2 role must be authority, got {flow1_history[1][3]}"
assert 'Level 1' in flow1_history[1][4], f"Event 2 designation must be Level 1, got {flow1_history[1][4]}"

assert flow1_history[2][0] == 'RESOLVED', f"Event 3 must be RESOLVED, got {flow1_history[2][0]}"
assert 'Amit Trivedi' in flow1_history[2][2], f"Event 3 actor must be Dr. Amit Trivedi, got {flow1_history[2][2]}"
assert 'Internal assessment component marks verified' in flow1_history[2][6], "Event 3 remarks missing"

print("\n>>> FLOW 1 VERIFICATION PASSED PERFECTLY!")

# ==============================================================================
# FLOW 2: Student Submits -> L1 Reviews -> L1 Forwards -> L2 Reviews -> L2 Resolves
# ==============================================================================
print("\n>>> TESTING FLOW 2: Student Submits -> L1 Reviews -> L1 Forwards -> L2 Reviews -> L2 Resolves")

# 1. Student submits complaint
set_acting_user(student['id'])
cur.execute('''
INSERT INTO public.complaints (
    student_id, department_id, current_authority_level_id,
    title, description, category, incident_date, status
) VALUES (
    %s, %s, %s,
    'MBA Capstone Project Off-Campus Sponsorship',
    'Seeking formal department sponsorship authorization for corporate project.',
    'Academic Affairs (Course Registration & Policy)',
    CURRENT_DATE,
    'PENDING'
) RETURNING id, tracking_number;
''', (student['id'], mba_dept_id, levels[1]['id']))
flow2_id, flow2_tracking = cur.fetchone()
print(f"[Flow 2] Grievance submitted: {flow2_tracking} (ID: {flow2_id})")

# 2. MBA L1 Faculty marks UNDER_REVIEW
set_acting_user(faculty['id'])
cur.execute('''
UPDATE public.complaints
SET status = 'UNDER_REVIEW',
    assigned_authority_id = %s,
    status_remarks = 'Reviewing corporate project guidelines.',
    updated_at = timezone('utc'::text, now())
WHERE id = %s;
''', (faculty['id'], flow2_id))
print(f"[Flow 2] L1 Dr. Amit Trivedi marked UNDER_REVIEW")

# 3. MBA L1 Faculty forwards to L2 (HoD)
set_acting_user(faculty['id'])
cur.execute('''
UPDATE public.complaints
SET status = 'ESCALATED',
    current_authority_level_id = %s,
    assigned_authority_id = NULL,
    status_remarks = 'Referred to HoD for corporate MOU approval.',
    updated_at = timezone('utc'::text, now())
WHERE id = %s;
''', (levels[2]['id'], flow2_id))
print(f"[Flow 2] L1 Dr. Amit Trivedi forwarded to Level 2 (HoD)")

# 4. MBA L2 HoD marks UNDER_REVIEW
set_acting_user(hod['id'])
cur.execute('''
UPDATE public.complaints
SET status = 'UNDER_REVIEW',
    assigned_authority_id = %s,
    status_remarks = 'HoD evaluating partnership compliance and student credentials.',
    updated_at = timezone('utc'::text, now())
WHERE id = %s;
''', (hod['id'], flow2_id))
print(f"[Flow 2] L2 Dr. Neha Gupta marked UNDER_REVIEW")

# 5. MBA L2 HoD resolves complaint
set_acting_user(hod['id'])
cur.execute('''
UPDATE public.complaints
SET status = 'RESOLVED',
    resolution_notes = 'Corporate MOU sanctioned. Project approval letter issued to student.',
    resolved_at = timezone('utc'::text, now()),
    updated_at = timezone('utc'::text, now())
WHERE id = %s;
''', (flow2_id,))
print(f"[Flow 2] L2 Dr. Neha Gupta marked RESOLVED")

# Verify Timeline for Flow 2
cur.execute('''
SELECT h.event_type, h.new_status, h.actor_display_name, h.actor_role,
       h.actor_designation, h.actor_department_name, h.remarks, h.created_at
FROM complaint_status_history h
WHERE h.complaint_id = %s
ORDER BY h.created_at ASC;
''', (flow2_id,))
flow2_history = cur.fetchall()

print(f"\n[Flow 2 Timeline Results] Total Events: {len(flow2_history)}")
for idx, h in enumerate(flow2_history, 1):
    print(f"  {idx}. [{h[0]}] Status: {h[1]}")
    print(f"     Actor: {h[2]} ({h[3]})")
    print(f"     Designation: {h[4]}")
    print(f"     Department: {h[5]}")
    print(f"     Remarks: {h[6]}")

# Assertions for Flow 2
assert len(flow2_history) == 5, f"Expected exactly 5 timeline events, found {len(flow2_history)}"
assert flow2_history[0][0] == 'SUBMITTED'
assert 'Rohan Verma' in flow2_history[0][2]

assert flow2_history[1][0] == 'UNDER_REVIEW'
assert 'Amit Trivedi' in flow2_history[1][2]

assert flow2_history[2][0] == 'FORWARDED'
assert 'Amit Trivedi' in flow2_history[2][2]

assert flow2_history[3][0] == 'UNDER_REVIEW'
assert 'Neha Gupta' in flow2_history[3][2]
assert flow2_history[3][3] == 'authority'
assert 'Level 2' in flow2_history[3][4]

assert flow2_history[4][0] == 'RESOLVED'
assert 'Neha Gupta' in flow2_history[4][2]
assert 'Corporate MOU sanctioned' in flow2_history[4][6]

print("\n>>> FLOW 2 VERIFICATION PASSED PERFECTLY!")

print("\n" + "=" * 60)
print("ALL DEMO FLOW VALIDATION TESTS COMPLETED WITH 100% SUCCESS!")
print("=" * 60)
