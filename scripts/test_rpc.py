import os, psycopg2
from dotenv import load_dotenv

load_dotenv('.env')
conn = psycopg2.connect(os.environ['DATABASE_URL'])
conn.autocommit = True
cur = conn.cursor()

# Get MCA student & faculty
cur.execute("SELECT id FROM profiles WHERE email = 'student.demo@campus.edu';")
student_id = cur.fetchone()[0]

cur.execute("SELECT id FROM profiles WHERE email = 'faculty.demo@campus.edu';")
faculty_id = cur.fetchone()[0]

cur.execute("SELECT id FROM departments WHERE code = 'MCA';")
mca_dept_id = cur.fetchone()[0]

cur.execute("SELECT id FROM authority_levels WHERE level_number = 1;")
lvl1_id = cur.fetchone()[0]

# 1. Create a dummy test complaint
cur.execute("""
INSERT INTO complaints (
    student_id, department_id, current_authority_level_id,
    title, description, category, incident_date, status, assigned_authority_id
) VALUES (
    %s, %s, %s,
    'Test Lab Collision RPC Test', 'Test description for forward rpc', 'Academic Affairs', CURRENT_DATE, 'PENDING', %s
) RETURNING id, tracking_number;
""", (student_id, mca_dept_id, lvl1_id, faculty_id))
dummy_id, dummy_track = cur.fetchone()
print(f"Created test complaint: {dummy_track} ({dummy_id})")

# 2. Call forward_grievance_to_next_tier as faculty
cur.execute("SELECT set_config('request.jwt.claim.sub', %s, false);", (str(faculty_id),))
cur.execute("SELECT public.forward_grievance_to_next_tier(%s, 'Lab collision test forward reason');", (dummy_id,))
res = cur.fetchone()[0]
print("RPC Result:", res)

# 3. Check complaint record
cur.execute("""
SELECT c.id, c.tracking_number, c.status, c.current_authority_level_id, al.level_number, c.assigned_authority_id, p.full_name
FROM complaints c
JOIN authority_levels al ON c.current_authority_level_id = al.id
LEFT JOIN profiles p ON c.assigned_authority_id = p.id
WHERE c.id = %s;
""", (dummy_id,))
print("Updated Complaint:", cur.fetchone())

# 4. Check status history
cur.execute("""
SELECT event_type, new_status, remarks, assigned_to_tier, assigned_to_name
FROM complaint_status_history
WHERE complaint_id = %s;
""", (dummy_id,))
for h in cur.fetchall():
    print("  History:", h)

# 5. Check complaint_escalations
cur.execute("""
SELECT from_level_id, to_level_id, reason FROM complaint_escalations WHERE complaint_id = %s;
""", (dummy_id,))
print("Escalations:", cur.fetchall())

# Clean up dummy test complaint
cur.execute("DELETE FROM complaints WHERE id = %s;", (dummy_id,))
print("Cleaned up dummy test complaint.")
