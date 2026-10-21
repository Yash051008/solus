'use server';
import { redirect } from 'next/navigation';
import { DomainError, nairaToKobo } from '@solus/core';
import { getRepo } from '@/lib/supabase/server';
import { sendOtpFor } from '@/lib/sms';
import { mutate, text } from '@/lib/forms';

const back = (fd: FormData) => `/retailer/${text(fd, 'orgId')}/orders`;

export async function cancelOrder(fd: FormData) {
  await mutate(back(fd), async () => {
    await (await getRepo()).orders.cancel(text(fd, 'orderId'), text(fd, 'reason'));
  }, 'Order cancelled and stock released.');
}

export async function confirmDelivery(fd: FormData) {
  await mutate(back(fd), async () => {
    await (await getRepo()).orders.confirmDelivery(text(fd, 'orderId'));
  }, 'Delivery confirmed.');
}

export async function disputeDelivery(fd: FormData) {
  await mutate(back(fd), async () => {
    await (await getRepo()).orders.disputeDelivery(text(fd, 'orderId'), text(fd, 'reason'));
  }, 'Problem reported to the distributor.');
}

/** Wallet-only settles now; any credit sends an OTP to the shop owner's phone first. */
export async function startPayment(fd: FormData) {
  const base = back(fd);
  let target: string;
  try {
    const r = await (await getRepo()).finance.startPayment(text(fd, 'orderId'), nairaToKobo(text(fd, 'wallet')), nairaToKobo(text(fd, 'credit')), text(fd, 'idempotencyKey'));
    if (r.status === 'pending_otp' && r.challenge_id) {
      await sendOtpFor(r.challenge_id);
      target = `${base}?challenge=${r.challenge_id}&order=${text(fd, 'orderId')}`;
    } else {
      target = `${base}?ok=${encodeURIComponent('Paid from your wallet.')}`;
    }
  } catch (err) {
    target = `${base}?error=${encodeURIComponent(err instanceof DomainError || err instanceof RangeError ? err.message : 'Payment failed.')}`;
  }
  redirect(target);
}

export async function verifyPayment(fd: FormData) {
  let message = '';
  await mutate(back(fd), async () => {
    let r;
    try {
      r = await (await getRepo()).push.verifyOtp(text(fd, 'challengeId'), text(fd, 'code'));
    } catch (err) {
      if (err instanceof Error && err.message === 'credit_limit_exceeded') {
        throw new RangeError('This would go over your credit limit with the distributor. Pay more from your wallet, or ask them to raise the limit.');
      }
      throw err;
    }
    if (!r.ok) throw new RangeError(r.reason === 'wrong_code' ? `Wrong code. ${r.attempts_left ?? 0} attempts left; pay again to get a new code.` : `Not confirmed (${r.reason}).`);
    message = 'Payment confirmed.';
  }, () => message);
}
