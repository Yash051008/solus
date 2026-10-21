-- OTP challenges (hard rule 5, ADR-0006): hashed at rest, expiring, attempt-limited, bound to one subject
-- record and both parties. Plaintext codes exist only in app.issue_otp_code's return value (service_role).

create table private.otp_challenges (
  id                uuid primary key default gen_random_uuid(),
  purpose           text not null check (purpose in ('handover', 'return', 'credit')),
  subject_kind      text not null check (subject_kind in ('shipment', 'order')),
  subject_id        uuid not null,
  initiator_user_id uuid not null references public.profiles (user_id),
  recipient_user_id uuid not null references public.profiles (user_id),
  payload_hash      text,
  code_hash         text,
  issue_count       integer not null default 0 check (issue_count between 0 and 3),
  attempts          integer not null default 0,
  max_attempts      integer not null default 5,
  status            text not null default 'pending' check (status in ('pending', 'verified', 'expired', 'locked', 'superseded')),
  expires_at        timestamptz,
  verified_at       timestamptz,
  created_at        timestamptz not null default now(),
  constraint otp_two_distinct_parties check (initiator_user_id <> recipient_user_id)
);
create unique index otp_one_pending_per_subject on private.otp_challenges (purpose, subject_id) where status = 'pending';
revoke all on private.otp_challenges from public, anon, authenticated, service_role;

-- Internal: opens a challenge (superseding any pending one for the same subject/purpose).
create function app.open_otp_challenge(
  p_purpose text, p_subject_kind text, p_subject_id uuid, p_initiator uuid, p_recipient uuid, p_payload_hash text default null
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_id uuid;
begin
  update private.otp_challenges set status = 'superseded'
   where purpose = p_purpose and subject_id = p_subject_id and status = 'pending';
  insert into private.otp_challenges (purpose, subject_kind, subject_id, initiator_user_id, recipient_user_id, payload_hash)
  values (p_purpose, p_subject_kind, p_subject_id, p_initiator, p_recipient, p_payload_hash)
  returning id into v_id;
  return v_id;
end;
$$;

-- service_role only (the SMS adapter): generates a fresh 6-digit code, stores only its bcrypt hash, and
-- returns the code + recipient phone exactly once. At most 3 issues per challenge.
create function app.issue_otp_code(p_challenge_id uuid)
returns table (code text, phone_e164 text, purpose text)
language plpgsql security definer set search_path = ''
as $$
declare
  v_c     private.otp_challenges;
  v_code  text;
  v_phone text;
begin
  select * into v_c from private.otp_challenges where id = p_challenge_id for update;
  if not found or v_c.status <> 'pending' then
    raise exception using errcode = 'SOL04', message = 'challenge is not pending';
  end if;
  if v_c.issue_count >= 3 then
    raise exception using errcode = 'SOL04', message = 'code re-sent too many times; start again';
  end if;
  select p.phone_e164 into v_phone from public.profiles p where p.user_id = v_c.recipient_user_id;
  if v_phone is null then
    raise exception using errcode = 'SOL05', message = 'recipient has no phone number on file';
  end if;
  v_code := lpad(((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint & 2147483647) % 1000000)::text, 6, '0');
  update private.otp_challenges
     set code_hash = extensions.crypt(v_code, extensions.gen_salt('bf', 8)),
         issue_count = issue_count + 1, attempts = 0, expires_at = now() + interval '5 minutes'
   where id = p_challenge_id;
  return query select v_code, v_phone, v_c.purpose;
end;
$$;

-- Initiator submits the code the recipient reads out. Wrong code => attempts++ and a RETURNED failure
-- (raising would roll back the counter). Success => the bound action runs in this same transaction.
create function app.verify_otp(p_challenge_id uuid, p_code text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := app.require_user();
  v_c   private.otp_challenges;
  v_result text;
begin
  select * into v_c from private.otp_challenges where id = p_challenge_id for update;
  if not found then
    raise exception using errcode = 'SOL05', message = 'challenge not found';
  end if;
  if v_c.initiator_user_id <> v_uid then
    raise exception using errcode = 'SOL03', message = 'only the person who started this handover can enter the code';
  end if;
  if v_c.status <> 'pending' then
    return jsonb_build_object('ok', false, 'reason', v_c.status);
  end if;
  if v_c.code_hash is null then
    return jsonb_build_object('ok', false, 'reason', 'code_not_sent');
  end if;
  if v_c.expires_at < now() then
    update private.otp_challenges set status = 'expired' where id = p_challenge_id;
    return jsonb_build_object('ok', false, 'reason', 'expired');
  end if;
  if p_code is null or extensions.crypt(p_code, v_c.code_hash) <> v_c.code_hash then
    update private.otp_challenges
       set attempts = attempts + 1,
           status = case when attempts + 1 >= max_attempts then 'locked' else status end
     where id = p_challenge_id;
    return jsonb_build_object('ok', false,
      'reason', case when v_c.attempts + 1 >= v_c.max_attempts then 'locked' else 'wrong_code' end,
      'attempts_left', greatest(v_c.max_attempts - v_c.attempts - 1, 0));
  end if;

  update private.otp_challenges set status = 'verified', verified_at = now() where id = p_challenge_id;
  if v_c.purpose = 'handover' then
    perform app.complete_push_handover(v_c.subject_id);
    v_result := 'open';
  elsif v_c.purpose = 'return' then
    v_result := app.complete_push_return(v_c.subject_id, v_c.payload_hash);
  else
    raise exception using errcode = 'SOL05', message = format('no action bound for purpose %s', v_c.purpose);
  end if;
  return jsonb_build_object('ok', true, 'purpose', v_c.purpose, 'result', v_result);
end;
$$;
