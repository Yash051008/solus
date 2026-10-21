'use server';
import { nairaToKobo } from '@solus/core';
import { getRepo } from '@/lib/supabase/server';
import { ensureVirtualAccount, simulateInboundTransfer } from '@/lib/payments';
import { mutate, text } from '@/lib/forms';

const back = (fd: FormData) => `/retailer/${text(fd, 'orgId')}/wallet`;

export async function createAccount(fd: FormData) {
  await mutate(back(fd), async () => {
    const orgId = text(fd, 'orgId');
    const owns = (await (await getRepo()).me.memberships()).some((m) => m.orgId === orgId && m.role === 'retailer' && m.status === 'active');
    if (!owns) throw new RangeError('Only the shop owner can create its account.');
    await ensureVirtualAccount(orgId, 'shop');
  }, 'Account number created.');
}

export async function simulateTopUp(fd: FormData) {
  let message = '';
  await mutate(back(fd), async () => {
    const r = await simulateInboundTransfer(text(fd, 'accountNumber'), nairaToKobo(text(fd, 'naira')), 'TEST TRANSFER');
    if (r.status !== 200) throw new RangeError(`Webhook returned ${r.status} (${r.result})`);
    message = `Test transfer delivered by webhook: ${r.result}.`;
  }, () => message);
}

export async function repayCredit(fd: FormData) {
  await mutate(back(fd), async () => {
    await (await getRepo()).finance.repayCredit(text(fd, 'distributorId'), text(fd, 'orgId'), nairaToKobo(text(fd, 'naira')), text(fd, 'idempotencyKey'));
  }, 'Credit repaid from your wallet.');
}
