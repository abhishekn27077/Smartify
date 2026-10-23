import os, psycopg2
from dotenv import load_dotenv

load_dotenv('.env')
conn = psycopg2.connect(os.environ['DATABASE_URL'])
conn.autocommit = True
cur = conn.cursor()

# Get HOD id
cur.execute("SELECT id FROM profiles WHERE email = 'hod.demo@campus.edu';")
hod_id = cur.fetchone()[0]

cur.execute("SELECT id FROM authority_levels WHERE level_number = 2;")
lvl2_id = cur.fetchone()[0]

# Clean duplicate test rows on SMT-2026-01074 status history
cur.execute("""
DELETE FROM complaint_status_history 
WHERE complaint_id = '54cd4b27-9d95-47c6-a28b-47fbd207298b'
  AND (event_type = 'UNDER_REVIEW' OR new_status = 'UNDER_REVIEW' OR (event_type = 'FORWARDED' AND assigned_to_tier LIKE '%Level 3%'));
""")

# SMT-2026-01074 is at Level 2, ESCALATED, assigned to Dr. Radhika Sharma
cur.execute("""
UPDATE complaints
SET current_authority_level_id = %s,
    assigned_authority_id = %s,
    status = 'ESCALATED',
    status_remarks = 'Forwarded to Level 2: Head of Department (HoD) for lab collision schedule resolution.'
WHERE id = '54cd4b27-9d95-47c6-a28b-47fbd207298b';
""", (lvl2_id, hod_id))

# Also ensure complaint_escalations has the forward record from L1 to L2
cur.execute("SELECT id FROM authority_levels WHERE level_number = 1;")
lvl1_id = cur.fetchone()[0]

cur.execute("SELECT id FROM profiles WHERE email = 'faculty.demo@campus.edu';")
fac_id = cur.fetchone()[0]

cur.execute("""
DELETE FROM complaint_escalations WHERE complaint_id = '54cd4b27-9d95-47c6-a28b-47fbd207298b';
""")

cur.execute("""
INSERT INTO complaint_escalations (
    complaint_id, from_level_id, to_level_id, escalated_by, is_automated, reason, tier_days_spent, created_at
) VALUES (
    '54cd4b27-9d95-47c6-a28b-47fbd207298b',
    %s, %s, %s, false,
    'Forwarded to Level 2: Head of Department (HoD) for lab collision schedule resolution.',
    1,
    '2026-10-19 15:55:47+00'
);
""", (lvl1_id, lvl2_id, fac_id))

# Ensure status history row has the assigned authority name and reason
cur.execute("""
UPDATE complaint_status_history
SET remarks = 'Forwarded to Level 2: Head of Department (HoD) for lab collision schedule resolution.',
    assigned_to_name = 'Dr. Radhika Sharma'
WHERE complaint_id = '54cd4b27-9d95-47c6-a28b-47fbd207298b'
  AND new_status = 'ESCALATED';
""")

print("SMT-2026-01074 prepared cleanly for HoD workflow testing.")
