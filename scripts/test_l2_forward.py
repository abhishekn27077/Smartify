import os, psycopg2
from dotenv import load_dotenv

load_dotenv('.env')
conn = psycopg2.connect(os.environ['DATABASE_URL'])
conn.autocommit = True
cur = conn.cursor()

# Get Dr. Radhika Sharma (MCA HoD, L2)
cur.execute("SELECT id, full_name, email FROM profiles WHERE email = 'hod.demo@campus.edu';")
hod_id, hod_name, hod_email = cur.fetchone()
print(f"HOD: {hod_name} ({hod_id})")

# Get Prof. M. K. Nair (MCA Dean, L3)
cur.execute("SELECT id, full_name, email FROM profiles WHERE email = 'dean.demo@campus.edu';")
dean_id, dean_name, dean_email = cur.fetchone()
print(f"Dean: {dean_name} ({dean_id})")

# Check SMT-2026-01074
cur.execute("""
SELECT c.id, c.tracking_number, c.status, al.level_number, al.title, c.assigned_authority_id, p.full_name, d.name
FROM complaints c
JOIN authority_levels al ON c.current_authority_level_id = al.id
JOIN departments d ON c.department_id = d.id
LEFT JOIN profiles p ON c.assigned_authority_id = p.id
WHERE c.tracking_number = 'SMT-2026-01074';
""")
c_row = cur.fetchone()
print("Current state of SMT-2026-01074:", c_row)

cid = c_row[0]

# Simulate HOD claiming if unassigned
cur.execute("SELECT set_config('request.jwt.claim.sub', %s, false);", (str(hod_id),))
cur.execute("SELECT public.claim_grievance(%s);", (cid,))
claim_res = cur.fetchone()[0]
print("Claim result:", claim_res)

# Check state after claim
cur.execute("""
SELECT c.id, c.tracking_number, c.status, al.level_number, al.title, c.assigned_authority_id, p.full_name
FROM complaints c
JOIN authority_levels al ON c.current_authority_level_id = al.id
LEFT JOIN profiles p ON c.assigned_authority_id = p.id
WHERE c.id = %s;
""", (cid,))
print("After claim:", cur.fetchone())

# Now test forwarding from L2 to L3 as HOD
cur.execute("SELECT public.forward_grievance_to_next_tier(%s, 'Requires Dean intervention for inter-departmental laboratory schedule coordination.');", (cid,))
fwd_res = cur.fetchone()[0]
print("Forward result from L2 to L3:", fwd_res)

# Check state after L2 -> L3 forward
cur.execute("""
SELECT c.id, c.tracking_number, c.status, al.level_number, al.title, c.assigned_authority_id, p.full_name, d.name
FROM complaints c
JOIN authority_levels al ON c.current_authority_level_id = al.id
JOIN departments d ON c.department_id = d.id
LEFT JOIN profiles p ON c.assigned_authority_id = p.id
WHERE c.id = %s;
""", (cid,))
print("After L2 -> L3 forward:", cur.fetchone())

# Check timeline history
cur.execute("""
SELECT event_type, new_status, actor_display_name, actor_designation, remarks, assigned_to_tier, assigned_to_name
FROM complaint_status_history
WHERE complaint_id = %s
ORDER BY created_at ASC;
""", (cid,))
print("\nTIMELINE:")
for h in cur.fetchall():
    print(" ", h)

# Reset SMT-2026-01074 back to L2 for Dr. Radhika Sharma demo test
cur.execute("SELECT id FROM authority_levels WHERE level_number = 2;")
lvl2_id = cur.fetchone()[0]

cur.execute("""
UPDATE complaints
SET current_authority_level_id = %s,
    assigned_authority_id = %s,
    status = 'UNDER_REVIEW',
    status_remarks = 'Case accepted by Dr. Radhika Sharma (Level 2 — Head of Department (HoD)).'
WHERE id = %s;
""", (lvl2_id, hod_id, cid))
print("\nReset SMT-2026-01074 to Level 2 (Assigned to Dr. Radhika Sharma, UNDER_REVIEW) for active testing.")
