'use server';
import { getRepo } from '@/lib/supabase/server';
import { mutate, optionalText, text } from '@/lib/forms';

export async function openTicket(fd: FormData) {
  await mutate('/support', async () => {
    const orderId = optionalText(fd, 'orderId');
    await (await getRepo()).support.open({
      openerOrgId: text(fd, 'orgId'), distributorId: text(fd, 'distributorId'), subject: text(fd, 'subject'),
      category: text(fd, 'category'), body: text(fd, 'body'), ...(orderId ? { orderId } : {}),
    });
  }, 'Ticket sent. You will be notified when the distributor replies.');
}

export async function replyTicket(fd: FormData) {
  await mutate('/support', async () => {
    await (await getRepo()).support.reply(text(fd, 'ticketId'), text(fd, 'body'));
  }, 'Reply sent.');
}
