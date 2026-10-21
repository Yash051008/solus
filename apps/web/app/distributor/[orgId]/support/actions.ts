'use server';
import { getRepo } from '@/lib/supabase/server';
import { mutate, text } from '@/lib/forms';

const back = (fd: FormData) => `/distributor/${text(fd, 'orgId')}/support`;

export async function reply(fd: FormData) {
  await mutate(back(fd), async () => { await (await getRepo()).support.reply(text(fd, 'ticketId'), text(fd, 'body')); }, 'Reply sent.');
}

export async function resolve(fd: FormData) {
  await mutate(back(fd), async () => { await (await getRepo()).support.resolve(text(fd, 'ticketId'), text(fd, 'resolution')); }, 'Ticket resolved.');
}
