import 'server-only';
import { redirect } from 'next/navigation';
import { DomainError } from '@solus/core';

export function text(fd: FormData, name: string): string {
  const v = fd.get(name);
  if (typeof v !== 'string' || v.trim() === '') throw new DomainError('validation_failed', `${name} is required`);
  return v.trim();
}

export function optionalText(fd: FormData, name: string): string | undefined {
  const v = fd.get(name);
  return typeof v === 'string' && v.trim() !== '' ? v.trim() : undefined;
}

export function num(fd: FormData, name: string): number {
  const n = Number(text(fd, name));
  if (!Number.isFinite(n)) throw new DomainError('validation_failed', `${name} must be a number`);
  return n;
}

export function optionalInt(fd: FormData, name: string): number | null {
  const v = optionalText(fd, name);
  if (v === undefined) return null;
  const n = Number(v);
  if (!Number.isSafeInteger(n)) throw new DomainError('validation_failed', `${name} must be a whole number`);
  return n;
}

function userMessage(err: unknown): string {
  if (err instanceof DomainError) return err.message;
  if (err instanceof RangeError) return err.message;
  console.error(err);
  return 'Something went wrong. Nothing was saved.';
}

/** Runs a mutation, then redirects back with a flash message. Never swallows Next's redirect signal. */
export async function mutate(backTo: string, fn: () => Promise<unknown>, okMessage: string): Promise<never> {
  let error: string | undefined;
  try {
    await fn();
  } catch (err) {
    error = userMessage(err);
  }
  const sep = backTo.includes('?') ? '&' : '?';
  redirect(error === undefined
    ? `${backTo}${sep}ok=${encodeURIComponent(okMessage)}`
    : `${backTo}${sep}error=${encodeURIComponent(error)}`);
}
