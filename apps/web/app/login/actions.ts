'use server';
import { redirect } from 'next/navigation';
import { createUserClient } from '@/lib/supabase/server';

function value(fd: FormData, name: string): string {
  const v = fd.get(name);
  return typeof v === 'string' ? v.trim() : '';
}

export async function signIn(fd: FormData) {
  const supabase = await createUserClient();
  const { error } = await supabase.auth.signInWithPassword({ email: value(fd, 'email'), password: value(fd, 'password') });
  if (error) redirect(`/login?error=${encodeURIComponent('Email or password is incorrect.')}`);
  redirect('/');
}

export async function signUp(fd: FormData) {
  const password = value(fd, 'password');
  if (password.length < 10) redirect(`/signup?error=${encodeURIComponent('Use at least 10 characters for your password.')}`);
  const supabase = await createUserClient();
  const { data, error } = await supabase.auth.signUp({ email: value(fd, 'email'), password });
  if (error) redirect(`/signup?error=${encodeURIComponent(error.message)}`);
  if (!data.session) redirect(`/login?ok=${encodeURIComponent('Check your email to confirm your account, then sign in.')}`);
  redirect('/onboarding');
}

export async function signOut() {
  const supabase = await createUserClient();
  await supabase.auth.signOut();
  redirect('/login');
}
