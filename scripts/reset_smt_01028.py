import psycopg2, os
from dotenv import load_dotenv

load_dotenv('.env')
conn = psycopg2.connect(os.environ.get('DATABASE_URL'))
conn.autocommit = True
cur = conn.cursor()

print("Resetting SMT-2026-01028 to MBA Level 1 Pending Intake...")

# Get MBA L1 authority level ID
cur.execute("SELECT id FROM authority_levels WHERE level_number = 1;")
lvl1_id = cur.fetchone()[0]

# Get MBA Faculty profile ID
cur.execute("SELECT id FROM profiles WHERE email = 'mba.faculty@campus.edu';")
faculty_id = cur.fetchone()[0]

# Reset complaint
cur.execute("""
UPDATE complaints
SET status = 'PENDING',
    current_authority_level_id = %s,
    assigned_authority_id = %s,
    status_remarks = 'Pending intake review by MBA Faculty Advisor.'
WHERE tracking_number = 'SMT-2026-01028';
""", (lvl1_id, faculty_id))

print("Complaint SMT-2026-01028 reset successfully to PENDING / Level 1 (Assigned: Dr. Amit Trivedi).")
