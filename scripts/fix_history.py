import os
import psycopg2
from dotenv import load_dotenv

load_dotenv('.env')
url = os.environ.get('DATABASE_URL')
conn = psycopg2.connect(url)
conn.autocommit = True
cur = conn.cursor()

# 1. Deduplicate records created within 5s of each other for the same complaint and new_status
print("--- Finding duplicates within 5 seconds ---")
cur.execute('''
SELECT h1.complaint_id, c.tracking_number, h1.new_status, h1.id as keep_id, h2.id as delete_id,
       h1.remarks as r1, h2.remarks as r2
FROM complaint_status_history h1
JOIN complaint_status_history h2 
  ON h1.complaint_id = h2.complaint_id 
 AND h1.new_status = h2.new_status 
 AND h1.id != h2.id 
 AND h1.created_at < h2.created_at
JOIN complaints c ON c.id = h1.complaint_id
WHERE EXTRACT(EPOCH FROM (h2.created_at - h1.created_at)) < 5;
''')
duplicates = cur.fetchall()
print(f"Found {len(duplicates)} duplicate pairs.")
for d in duplicates:
    complaint_id, tracking, status, keep_id, delete_id, r1, r2 = d
    best_remark = r2 if (r2 and len(r2) > len(r1 or '')) else r1
    print(f"Complaint {tracking} ({status}): keeping {keep_id} with remark '{best_remark}', deleting {delete_id}")
    cur.execute('''
        UPDATE complaint_status_history 
        SET remarks = %s 
        WHERE id = %s;
    ''', (best_remark, keep_id))
    cur.execute('''
        DELETE FROM complaint_status_history 
        WHERE id = %s;
    ''', (delete_id,))

# 2. Backfill snapshot fields on complaint_status_history
print("\n--- Backfilling snapshot fields ---")
cur.execute('''
UPDATE public.complaint_status_history h
SET 
    actor_user_id = h.changed_by,
    actor_display_name = CASE 
        WHEN h.changed_by IS NULL THEN 'System Redressal Engine (AUTOMATED)'
        ELSE p.full_name
    END,
    actor_role = CASE 
        WHEN h.changed_by IS NULL THEN 'SYSTEM'
        ELSE p.role::text
    END,
    actor_department_id = p.department_id,
    actor_department_name = d.name,
    actor_authority_level = al.level_number,
    actor_designation = CASE 
        WHEN h.changed_by IS NULL THEN 'Automated System'
        WHEN p.role = 'student' THEN COALESCE(p.academic_program || ' Student', 'Student')
        ELSE p.designation
    END,
    event_type = CASE 
        WHEN h.new_status = 'PENDING' THEN 'SUBMITTED'
        WHEN h.new_status = 'UNDER_REVIEW' THEN 'UNDER_REVIEW'
        WHEN h.new_status = 'RESOLVED' THEN 'RESOLVED'
        WHEN h.new_status = 'REJECTED' THEN 'REJECTED'
        WHEN h.new_status = 'ESCALATED' AND h.changed_by IS NULL THEN 'SYSTEM_ESCALATION'
        WHEN h.new_status = 'ESCALATED' THEN 'FORWARDED'
        WHEN h.new_status = 'CUTOFF_PAUSED' THEN 'PAUSED'
        ELSE 'STATUS_CHANGE'
    END,
    is_system_event = (h.changed_by IS NULL)
FROM public.complaint_status_history h2
LEFT JOIN public.profiles p ON p.id = h2.changed_by
LEFT JOIN public.departments d ON d.id = p.department_id
LEFT JOIN public.authority_levels al ON al.id = p.authority_level_id
WHERE h.id = h2.id;
''')

# For SMT-2026-01033 specifically, verify timeline
cur.execute('''
SELECT h.id, h.event_type, h.new_status, h.actor_display_name, h.actor_role, 
       h.actor_designation, h.actor_department_name, h.remarks, h.created_at
FROM complaint_status_history h
JOIN complaints c ON c.id = h.complaint_id
WHERE c.tracking_number = 'SMT-2026-01033'
ORDER BY h.created_at ASC;
''')
rows = cur.fetchall()
print("\n--- SMT-2026-01033 Timeline ---")
for r in rows:
    print(r)

print("\nBackfill complete.")
