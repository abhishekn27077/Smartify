import os, psycopg2
from dotenv import load_dotenv

load_dotenv('.env')
conn = psycopg2.connect(os.environ['DATABASE_URL'])
conn.autocommit = True
cur = conn.cursor()

with open('supabase/migrations/20261020000001_authority_workflow_claim_and_escalation_repair.sql', 'r', encoding='utf-8') as f:
    sql = f.read()

cur.execute(sql)
print("Migration applied successfully!")

# Check SMT-2026-01074 state
cur.execute("""
SELECT c.id, c.tracking_number, c.title, c.status, al.level_number, al.title, c.assigned_authority_id, p.full_name, p.email
FROM complaints c
JOIN authority_levels al ON c.current_authority_level_id = al.id
LEFT JOIN profiles p ON c.assigned_authority_id = p.id
WHERE c.tracking_number = 'SMT-2026-01074';
""")
print("SMT-2026-01074 after migration:", cur.fetchone())
