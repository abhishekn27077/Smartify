import os
import psycopg2
from dotenv import load_dotenv

load_dotenv('.env')
url = os.environ.get('DATABASE_URL')
conn = psycopg2.connect(url)
conn.autocommit = True
cur = conn.cursor()

print("=" * 70)
print("SMARTIFY - SECTION 17 END-TO-END VALIDATION SUITE (A THROUGH K)")
print("=" * 70)

def set_acting_user(user_id):
    cur.execute("SELECT set_config('request.jwt.claim.sub', %s, false);", (str(user_id),))

# Fetch profiles
cur.execute("""
SELECT id, full_name, email, role, department_id, authority_level_id, designation
FROM profiles
WHERE email IN (
    'student.demo@campus.edu',
    'faculty.demo@campus.edu',
    'hod.demo@campus.edu',
    'dean.demo@campus.edu',
    'mba.student@campus.edu',
    'mba.faculty@campus.edu',
    'mba.hod@campus.edu',
    'mba.dean@campus.edu',
    'mcom.student@campus.edu',
    'mcom.faculty@campus.edu',
    'mcom.hod@campus.edu',
    'mcom.dean@campus.edu',
    'it.demo@campus.edu',
    'authority.demo@campus.edu',
    'finance.demo@campus.edu',
    'infra.demo@campus.edu',
    'admin.demo@campus.edu'
);
""")
profiles = {r[2]: {
    'id': r[0], 'name': r[1], 'email': r[2], 'role': r[3],
    'dept_id': r[4], 'level_id': r[5], 'designation': r[6]
} for r in cur.fetchall()}

# Fetch departments
cur.execute("SELECT id, code, name FROM departments;")
departments = {r[1]: {'id': r[0], 'name': r[2]} for r in cur.fetchall()}

# Fetch authority levels
cur.execute("SELECT id, level_number, title FROM authority_levels ORDER BY level_number;")
levels = {r[1]: {'id': r[0], 'title': r[2]} for r in cur.fetchall()}

created_grievance_ids = []

try:
    # --------------------------------------------------------------------------
    # TEST A: Submit new MCA academic grievance -> appears at/near top of MCA L1 queue
    # --------------------------------------------------------------------------
    print("\n--- TEST A: Submit new MCA academic grievance ---")
    set_acting_user(profiles['student.demo@campus.edu']['id'])
    cur.execute("""
    INSERT INTO public.complaints (
        student_id, department_id, current_authority_level_id,
        title, description, category, incident_date, status
    ) VALUES (
        %s, %s, %s,
        'MCA Lab Server Connectivity Downtime',
        'Unable to access cloud lab environment during MCA practical hours.',
        'Academic Affairs — Lab Facilities',
        CURRENT_DATE,
        'PENDING'
    ) RETURNING id, tracking_number;
    """, (profiles['student.demo@campus.edu']['id'], departments['MCA']['id'], levels[1]['id']))
    test_a_id, test_a_tracking = cur.fetchone()
    created_grievance_ids.append(test_a_id)
    print(f"Submitted MCA grievance: {test_a_tracking} (ID: {test_a_id})")

    # Check MCA L1 queue
    set_acting_user(profiles['faculty.demo@campus.edu']['id'])
    cur.execute("SELECT public.get_authority_redressal_queue('ALL', 'PRIORITY_SLA', NULL);")
    mca_l1_queue = cur.fetchone()[0]
    
    # Check that test_a_tracking is in the top 2
    top_tracking = [item['tracking_number'] for item in mca_l1_queue[:2]]
    print(f"MCA L1 Queue Top items: {top_tracking}")
    assert test_a_tracking in top_tracking, f"Expected {test_a_tracking} in top 2, got {top_tracking}"
    print(f"[PASS] TEST A: {test_a_tracking} appears at/near top of MCA L1 queue.")

    # --------------------------------------------------------------------------
    # TEST B: Submit another newer MCA grievance -> newer grievance appears ABOVE older same-priority
    # --------------------------------------------------------------------------
    print("\n--- TEST B: Submit newer MCA grievance and check ordering ---")
    set_acting_user(profiles['student.demo@campus.edu']['id'])
    cur.execute("""
    INSERT INTO public.complaints (
        student_id, department_id, current_authority_level_id,
        title, description, category, incident_date, status
    ) VALUES (
        %s, %s, %s,
        'MCA Semester Elective Registration Bug',
        'System throws 500 error when selecting MCA AI elective course.',
        'Academic Affairs — Course Registration',
        CURRENT_DATE,
        'PENDING'
    ) RETURNING id, tracking_number;
    """, (profiles['student.demo@campus.edu']['id'], departments['MCA']['id'], levels[1]['id']))
    test_b_id, test_b_tracking = cur.fetchone()
    created_grievance_ids.append(test_b_id)
    print(f"Submitted newer MCA grievance: {test_b_tracking} (ID: {test_b_id})")

    # Check MCA L1 queue order
    set_acting_user(profiles['faculty.demo@campus.edu']['id'])
    cur.execute("SELECT public.get_authority_redressal_queue('ALL', 'PRIORITY_SLA', NULL);")
    mca_l1_queue = cur.fetchone()[0]
    
    # In Priority group 3 (Pending Intake), newest created_at must come FIRST
    b_idx = next(i for i, item in enumerate(mca_l1_queue) if item['tracking_number'] == test_b_tracking)
    a_idx = next(i for i, item in enumerate(mca_l1_queue) if item['tracking_number'] == test_a_tracking)
    print(f"Order: {test_b_tracking} index={b_idx}, {test_a_tracking} index={a_idx}")
    assert b_idx < a_idx, f"Expected {test_b_tracking} (idx {b_idx}) to appear before {test_a_tracking} (idx {a_idx})"
    print(f"[PASS] TEST B: Newer grievance {test_b_tracking} appears before older grievance {test_a_tracking}!")

    # --------------------------------------------------------------------------
    # TEST C: MCA L1 opens grievance -> verify department and authority scope
    # --------------------------------------------------------------------------
    print("\n--- TEST C: MCA L1 opens grievance -> verify department & authority scope ---")
    set_acting_user(profiles['faculty.demo@campus.edu']['id'])
    cur.execute("""
    SELECT c.tracking_number, d.name, c.current_authority_level_id, al.title
    FROM public.complaints c
    JOIN departments d ON d.id = c.department_id
    JOIN authority_levels al ON al.id = c.current_authority_level_id
    WHERE c.id = %s;
    """, (test_b_id,))
    row = cur.fetchone()
    print(f"Grievance details: Tracking={row[0]}, Dept={row[1]}, Level={row[3]}")
    assert row[1] == 'Department of MCA', f"Expected Department of MCA, got {row[1]}"
    assert 'Faculty / Department Officer' in row[3], f"Expected clean L1 title, got {row[3]}"
    print("[PASS] TEST C: Grievance has correct MCA department and L1 authority scope.")

    # --------------------------------------------------------------------------
    # TEST D: MCA L1 -> Under Review -> queue status changes
    # --------------------------------------------------------------------------
    print("\n--- TEST D: MCA L1 -> Under Review ---")
    set_acting_user(profiles['faculty.demo@campus.edu']['id'])
    cur.execute("""
    UPDATE public.complaints
    SET status = 'UNDER_REVIEW',
        status_remarks = 'Acknowledged by MCA Faculty Advisor. Investigating registration portal logs.',
        assigned_authority_id = %s,
        updated_at = timezone('utc', now())
    WHERE id = %s;
    """, (profiles['faculty.demo@campus.edu']['id'], test_b_id))
    
    # Verify in queue
    cur.execute("SELECT public.get_authority_redressal_queue('UNDER_REVIEW', 'PRIORITY_SLA', NULL);")
    ur_queue = cur.fetchone()[0]
    ur_trackings = [item['tracking_number'] for item in ur_queue]
    assert test_b_tracking in ur_trackings, f"Expected {test_b_tracking} in UNDER_REVIEW queue, got {ur_trackings}"
    print(f"[PASS] TEST D: Grievance status successfully transitioned to UNDER_REVIEW in queue.")

    # --------------------------------------------------------------------------
    # TEST E: MCA L1 -> Resolve -> resolved by actual MCA L1 identity
    # --------------------------------------------------------------------------
    print("\n--- TEST E: MCA L1 -> Resolve -> check identity in status history & timeline ---")
    set_acting_user(profiles['faculty.demo@campus.edu']['id'])
    cur.execute("""
    UPDATE public.complaints
    SET status = 'RESOLVED',
        status_remarks = 'Resolved by Faculty Advisor.',
        resolution_notes = 'Portal glitch cleared by sysadmin; student successfully enrolled in elective.',
        resolved_at = timezone('utc', now()),
        updated_at = timezone('utc', now())
    WHERE id = %s;
    """, (test_b_id,))

    # Check status history snapshot for actor identity
    cur.execute("""
    SELECT actor_display_name, actor_role, actor_designation, is_system_event, new_status
    FROM public.complaint_status_history
    WHERE complaint_id = %s AND new_status = 'RESOLVED'
    ORDER BY created_at DESC LIMIT 1;
    """, (test_b_id,))
    history_row = cur.fetchone()
    print(f"Status history entry: Name={history_row[0]}, Role={history_row[1]}, Designation={history_row[2]}, System={history_row[3]}")
    assert history_row[0] == profiles['faculty.demo@campus.edu']['name'], f"Expected {profiles['faculty.demo@campus.edu']['name']}, got {history_row[0]}"
    assert "Unknown User" not in history_row[0], "Actor full name must never be Unknown User"
    assert history_row[3] == False, "Human resolution action must not be labeled as system event"
    print("[PASS] TEST E: Grievance resolved by authenticated authority profile identity.")

    # --------------------------------------------------------------------------
    # TEST F: MCA L1 -> Forward -> next valid MCA L2 is found & updated
    # --------------------------------------------------------------------------
    print("\n--- TEST F: MCA L1 -> Forward to Level 2 ---")
    set_acting_user(profiles['faculty.demo@campus.edu']['id'])
    cur.execute("""
    SELECT public.forward_grievance_to_next_tier(%s, 'Requires HoD sanction for lab server hardware allocation.');
    """, (test_a_id,))
    forward_result = cur.fetchone()[0]
    print(f"Forward result: {forward_result}")
    assert forward_result['success'] == True, f"Forwarding failed: {forward_result}"
    assert forward_result['to_level_number'] == 2, f"Expected forwarded to level 2, got {forward_result['to_level_number']}"
    assert forward_result['assigned_authority_name'] == profiles['hod.demo@campus.edu']['name'], f"Expected HoD, got {forward_result['assigned_authority_name']}"

    # Verify grievance in MCA L2 queue
    set_acting_user(profiles['hod.demo@campus.edu']['id'])
    cur.execute("SELECT public.get_authority_redressal_queue('ALL', 'PRIORITY_SLA', NULL);")
    hod_queue = cur.fetchone()[0]
    hod_trackings = [item['tracking_number'] for item in hod_queue]
    assert test_a_tracking in hod_trackings, f"Expected {test_a_tracking} in HoD queue, got {hod_trackings}"
    print(f"[PASS] TEST F: Successfully forwarded to MCA Level 2 HoD ({profiles['hod.demo@campus.edu']['name']})!")

    # --------------------------------------------------------------------------
    # TEST G: MBA L1 queue -> MBA grievances only
    # --------------------------------------------------------------------------
    print("\n--- TEST G: MBA L1 queue -> MBA grievances only ---")
    set_acting_user(profiles['mba.faculty@campus.edu']['id'])
    cur.execute("SELECT public.get_authority_redressal_queue('ALL', 'PRIORITY_SLA', NULL);")
    mba_queue = cur.fetchone()[0]
    print(f"MBA L1 Queue count: {len(mba_queue)}")
    for item in mba_queue:
        assert item['departments']['name'] == 'Department of MBA', f"Non-MBA item found: {item}"
    print("[PASS] TEST G: MBA L1 queue contains MBA grievances only.")

    # --------------------------------------------------------------------------
    # TEST H: MCA authority must not see MBA grievances
    # --------------------------------------------------------------------------
    print("\n--- TEST H: MCA authority must not see MBA grievances ---")
    set_acting_user(profiles['faculty.demo@campus.edu']['id'])
    cur.execute("SELECT public.get_authority_redressal_queue('ALL', 'PRIORITY_SLA', NULL);")
    mca_queue = cur.fetchone()[0]
    for item in mca_queue:
        assert item['departments']['name'] == 'Department of MCA', f"MCA saw non-MCA item: {item}"
    print("[PASS] TEST H: MCA authority has zero visibility into MBA grievances.")

    # --------------------------------------------------------------------------
    # TEST I: Operational Wi-Fi complaint from MCA student -> Library & IT Services
    # --------------------------------------------------------------------------
    print("\n--- TEST I: Operational Wi-Fi complaint from MCA student -> Library & IT Services ---")
    set_acting_user(profiles['student.demo@campus.edu']['id'])
    cur.execute("""
    INSERT INTO public.complaints (
        student_id, department_id, current_authority_level_id,
        title, description, category, incident_date, status
    ) VALUES (
        %s, %s, %s,
        'Campus Hostel Wi-Fi AP Offline',
        'Access point on Block B 2nd floor is not emitting SSID.',
        'Campus Infrastructure & Facilities (Wi-Fi & Network)',
        CURRENT_DATE,
        'PENDING'
    ) RETURNING id, tracking_number;
    """, (profiles['student.demo@campus.edu']['id'], departments['IT']['id'], levels[1]['id']))
    wifi_id, wifi_tracking = cur.fetchone()
    created_grievance_ids.append(wifi_id)
    print(f"Submitted Wi-Fi grievance: {wifi_tracking}")

    # IT Officer checks queue
    set_acting_user(profiles['it.demo@campus.edu']['id'])
    cur.execute("SELECT public.get_authority_redressal_queue('ALL', 'PRIORITY_SLA', NULL);")
    it_queue = cur.fetchone()[0]
    it_trackings = [item['tracking_number'] for item in it_queue]
    assert wifi_tracking in it_trackings, f"Expected {wifi_tracking} in IT queue, got {it_trackings}"

    # MCA Faculty checks queue -> MUST NOT BE PRESENT
    set_acting_user(profiles['faculty.demo@campus.edu']['id'])
    cur.execute("SELECT public.get_authority_redressal_queue('ALL', 'PRIORITY_SLA', NULL);")
    mca_queue_after = cur.fetchone()[0]
    mca_trackings_after = [item['tracking_number'] for item in mca_queue_after]
    assert wifi_tracking not in mca_trackings_after, f"Scope violation: MCA saw Wi-Fi grievance {wifi_tracking}"
    print("[PASS] TEST I: Operational Wi-Fi grievance routed to Library & IT Services, not MCA!")

    # --------------------------------------------------------------------------
    # TEST J: Hostel complaint from MBA student -> Hostel & Residential Life
    # --------------------------------------------------------------------------
    print("\n--- TEST J: Hostel complaint from MBA student -> Hostel & Residential Life ---")
    set_acting_user(profiles['mba.student@campus.edu']['id'])
    cur.execute("""
    INSERT INTO public.complaints (
        student_id, department_id, current_authority_level_id,
        title, description, category, incident_date, status
    ) VALUES (
        %s, %s, %s,
        'Hostel Room Water Leakage',
        'Water leaking from ceiling pipe in room 304.',
        'Campus Infrastructure & Facilities (Hostel Maintenance)',
        CURRENT_DATE,
        'PENDING'
    ) RETURNING id, tracking_number;
    """, (profiles['mba.student@campus.edu']['id'], departments['HOSTEL']['id'], levels[1]['id']))
    hostel_id, hostel_tracking = cur.fetchone()
    created_grievance_ids.append(hostel_id)
    print(f"Submitted Hostel grievance: {hostel_tracking}")

    # Hostel Warden checks queue
    set_acting_user(profiles['authority.demo@campus.edu']['id'])
    cur.execute("SELECT public.get_authority_redressal_queue('ALL', 'PRIORITY_SLA', NULL);")
    hostel_queue = cur.fetchone()[0]
    hostel_trackings = [item['tracking_number'] for item in hostel_queue]
    assert hostel_tracking in hostel_trackings, f"Expected {hostel_tracking} in Hostel queue, got {hostel_trackings}"

    # MBA Faculty checks queue -> MUST NOT BE PRESENT
    set_acting_user(profiles['mba.faculty@campus.edu']['id'])
    cur.execute("SELECT public.get_authority_redressal_queue('ALL', 'PRIORITY_SLA', NULL);")
    mba_queue_after = cur.fetchone()[0]
    mba_trackings_after = [item['tracking_number'] for item in mba_queue_after]
    assert hostel_tracking not in mba_trackings_after, f"Scope violation: MBA saw Hostel grievance {hostel_tracking}"
    print("[PASS] TEST J: Hostel complaint from MBA student routed to Hostel & Residential Life, not MBA!")

    # --------------------------------------------------------------------------
    # TEST K: Admin analytics -> institute-wide exact counts
    # --------------------------------------------------------------------------
    print("\n--- TEST K: Admin analytics -> institute-wide exact counts ---")
    set_acting_user(profiles['admin.demo@campus.edu']['id'])
    
    # 1. Total counts across institute
    cur.execute("""
    SELECT
        count(*) as total_all,
        count(*) filter (where status = 'PENDING') as pending,
        count(*) filter (where status = 'UNDER_REVIEW') as under_review,
        count(*) filter (where status = 'RESOLVED') as resolved,
        count(*) filter (where status = 'REJECTED') as rejected,
        count(*) filter (where status = 'ESCALATED') as escalated,
        count(*) filter (where status = 'CUTOFF_PAUSED') as paused
    FROM public.complaints;
    """)
    db_counts = cur.fetchone()
    print(f"Institute-wide total: {db_counts[0]}, Pending: {db_counts[1]}, Under Review: {db_counts[2]}, Resolved: {db_counts[3]}")

    # 2. Department-level breakdown
    cur.execute("""
    SELECT d.name, count(c.id)
    FROM departments d
    LEFT JOIN complaints c ON c.department_id = d.id
    GROUP BY d.name
    ORDER BY d.name;
    """)
    dept_breakdown = cur.fetchall()
    print("Department breakdowns:")
    for name, cnt in dept_breakdown:
        print(f"   - {name}: {cnt} complaints")

    # Verify admin summary query
    cur.execute("SELECT public.get_authority_queue_summary();")
    admin_summary = cur.fetchone()[0]
    print(f"Admin queue summary: {admin_summary}")
    assert admin_summary['total_active'] == (db_counts[1] + db_counts[2] + db_counts[5] + db_counts[6]), \
        f"Active summary mismatch: summary={admin_summary['total_active']} vs sum={db_counts[1] + db_counts[2] + db_counts[5] + db_counts[6]}"
    print("[PASS] TEST K: Admin has institute-wide exact counts and department breakdowns.")

    print("\n" + "=" * 70)
    print("ALL TESTS (A THROUGH K) PASSED 100% CLEANLY!")
    print("=" * 70)

finally:
    # Cleanup test records
    if created_grievance_ids:
        print(f"\nCleaning up {len(created_grievance_ids)} test grievances...")
        id_strs = [str(x) for x in created_grievance_ids]
        cur.execute("DELETE FROM public.audit_logs WHERE entity_type = 'complaint' AND entity_id::text = ANY(%s);", (id_strs,))
        cur.execute("DELETE FROM public.complaints WHERE id::text = ANY(%s);", (id_strs,))
        print("Cleanup completed successfully.")
    conn.close()
