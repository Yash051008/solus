'use server';
import { redirect } from 'next/navigation';
import { DomainError } from '@solus/core';
import { getRepo } from '@/lib/supabase/server';
import { sendOtpFor } from '@/lib/sms';
import { mutate, optionalText, text } from '@/lib/forms';

const back = (fd: FormData) => `/distributor/${text(fd, 'orgId')}/push?w=${text(fd, 'w')}`;

function errorText(err: unknown): string {
  return err instanceof DomainError || err instanceof RangeError ? err.message : 'Something went wrong. Nothing was saved.';
}

export async function decideRequest(fd: FormData) {
  const approve = text(fd, 'decision') === 'approve';
  await mutate(back(fd), async () => {
    await (await getRepo()).push.decideStockRequest(text(fd, 'requestId'), approve, optionalText(fd, 'reason'));
  }, approve ? 'Approved. Hand the stock over with the agent present.' : 'Request rejected.');
}

/** Opens the OTP challenge (as the signed-in staff member), then the SMS adapter sends the code. */
async function startWithOtp(fd: FormData, what: string, open: () => Promise<string>) {
  let target: string;
  try {
    const challengeId = await open();
    const { sentTo } = await sendOtpFor(challengeId);
    target = `${back(fd)}&challenge=${challengeId}&sentTo=${encodeURIComponent(sentTo)}&what=${encodeURIComponent(what)}`;
  } catch (err) {
    target = `${back(fd)}&error=${encodeURIComponent(errorText(err))}`;
  }
  redirect(target);
}

export async function startHandover(fd: FormData) {
  await startWithOtp(fd, 'stock handover', async () => (await getRepo()).push.startHandover(text(fd, 'shipmentId')));
}

export async function startReturn(fd: FormData) {
  await startWithOtp(fd, 'return count', async () => {
    const counts = new Map<string, { qtyPieces: number; damaged: number }>();
    for (const [k, v] of fd.entries()) {
      const [kind, skuId] = k.split(':');
      if ((kind !== 'r' && kind !== 'd') || !skuId || typeof v !== 'string') continue;
      const n = Number(v || '0');
      if (!Number.isSafeInteger(n) || n < 0) throw new RangeError('Counts must be whole numbers.');
      const e = counts.get(skuId) ?? { qtyPieces: 0, damaged: 0 };
      if (kind === 'r') e.qtyPieces = n; else e.damaged = n;
      counts.set(skuId, e);
    }
    return (await getRepo()).push.startReturn(text(fd, 'shipmentId'), [...counts.entries()].map(([skuId, c]) => ({ skuId, ...c })));
  });
}

const REASONS: Record<string, string> = {
  wrong_code: 'Wrong code.', locked: 'Too many wrong codes. Start again to send a new code.', expired: 'The code expired. Start again.',
  verified: 'Already confirmed.', superseded: 'A newer code was sent; use that one.', code_not_sent: 'No code was sent yet.',
};

export async function verifyOtp(fd: FormData) {
  const challengeId = text(fd, 'challengeId');
  let target: string;
  try {
    const r = await (await getRepo()).push.verifyOtp(challengeId, text(fd, 'code'));
    if (r.ok) {
      const message = r.purpose === 'handover' ? 'Handover confirmed. The agent now carries the stock.'
        : r.result === 'closed' ? 'Return confirmed. Shipment closed.' : 'Return confirmed. Unaccounted stock is waiting for manager approval.';
      target = `${back(fd)}&ok=${encodeURIComponent(message)}`;
    } else {
      const message = `${REASONS[r.reason ?? ''] ?? 'Not confirmed.'}${r.reason === 'wrong_code' && r.attempts_left !== undefined ? ` ${r.attempts_left} attempts left.` : ''}`;
      // Only a wrong code keeps the same challenge usable; every other failure needs a fresh start.
      const keep = r.reason === 'wrong_code'
        ? `&challenge=${challengeId}&sentTo=${encodeURIComponent(text(fd, 'sentTo'))}&what=${encodeURIComponent(text(fd, 'what'))}` : '';
      target = `${back(fd)}${keep}&error=${encodeURIComponent(message)}`;
    }
  } catch (err) {
    target = `${back(fd)}&error=${encodeURIComponent(errorText(err))}`;
  }
  redirect(target);
}

export async function acceptIntoVariance(fd: FormData) {
  let message = '';
  await mutate(back(fd), async () => {
    const r = await (await getRepo()).push.acceptIntoVariance(text(fd, 'itemId'), text(fd, 'note'));
    message = r.unrecorded_pieces > 0
      ? `Sale recorded. ${r.unrecorded_pieces} pieces beyond recorded stock are now a pending variance case.`
      : 'Sale recorded.';
  }, () => message);
}

export async function dismissReview(fd: FormData) {
  await mutate(back(fd), async () => {
    await (await getRepo()).push.dismissReview(text(fd, 'itemId'), text(fd, 'note'));
  }, 'Dismissed.');
}

export async function resolveVariance(fd: FormData) {
  const raw = text(fd, 'decision');
  const decision = raw === 'charge_agent' || raw === 'link_handover' ? raw : 'write_off';
  let message = '';
  await mutate(back(fd), async () => {
    const r = await (await getRepo()).push.resolveVariance(text(fd, 'caseId'), decision, text(fd, 'note'));
    message = `${decision === 'write_off' ? 'Resolved' : decision === 'charge_agent' ? 'Charged to the agent' : 'Linked to the missed handover'}.${r === 'closed' ? ' Shipment closed.' : ''}`;
  }, () => message);
}
