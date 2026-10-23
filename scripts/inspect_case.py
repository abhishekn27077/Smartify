import os, psycopg2
from dotenv import load_dotenv

load_dotenv('.env')
conn = psycopg2.connect(os.environ['DATABASE_URL'])
conn.autocommit = True
cur = conn.cursor()

# Get faculty id
cur.execute("SELECT id FROM profiles WHERE email = 'faculty.demo@campus.edu';")
fac_id = cur.fetchone()[0]

# Set acting user
cur.execute("SELECT set_config('request.jwt.claim.sub', %s, false);", (str(fac_id),))

# Check SMT-2026-01074 current state
cur.execute("""
SELECT c.id, c.tracking_number, c.status, c.current_authority_level_id, al.level_number, c.assigned_authority_id
FROM complaints c
JOIN authority_levels al ON c.current_authority_level_id = al.id
WHERE c.tracking_number = 'SMT-2026-01074';
""")
print("SMT-2026-01074:", cur.fetchone())
