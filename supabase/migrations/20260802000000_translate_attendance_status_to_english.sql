-- Translate attendance.status values from Indonesian to English to match the
-- renamed AttendanceStatus enum in lib/features/staff/presentation/staff_attendance_screen.dart
-- (hadir -> present, izin -> permission, sakit -> sick, alpha -> absent, cuti -> leave).
--
-- attendance_status_check also allowed 'terlambat' (late), a value the Flutter
-- enum never handled (unmatched values silently fell through to the default
-- case, AttendanceStatus.hadir/present) — no rows used it at migration time,
-- but it's translated here too ('late') so the constraint keeps the same
-- shape instead of silently dropping an allowed value.
--
-- The constraint must be dropped before the data is updated (it validates
-- against the new set on add), then re-created against the English values.
alter table public.attendance drop constraint if exists attendance_status_check;

update public.attendance set status = 'present'    where status = 'hadir';
update public.attendance set status = 'permission' where status = 'izin';
update public.attendance set status = 'sick'       where status = 'sakit';
update public.attendance set status = 'absent'     where status = 'alpha';
update public.attendance set status = 'leave'      where status = 'cuti';
update public.attendance set status = 'late'       where status = 'terlambat';

alter table public.attendance add constraint attendance_status_check
  check (status::text = any (array['present','permission','sick','leave','absent','late']::text[]));
