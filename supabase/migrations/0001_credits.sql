-- Per My Last: shared-key credits. One row per user; 1 credit = 1 rewrite.
-- All writes go through service-role edge functions / security-definer RPCs,
-- never from the app, so users cannot edit their own balance.

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  credits integer not null default 0 check (credits >= 0),
  credits_limit integer not null default 1000,
  subscription_status text not null default 'none',
  stripe_customer_id text unique,
  stripe_subscription_id text,
  current_period_end timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Users may read only their own row (the app shows the balance from this).
create policy "read own profile" on public.profiles
  for select using (auth.uid() = user_id);

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (user_id) values (new.id) on conflict do nothing;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Atomically spend one credit. Returns the new balance, or null when the user
-- has no credits or no active subscription. A single UPDATE means two parallel
-- requests can never overspend.
create or replace function public.consume_credit(p_user uuid) returns integer
language sql security definer set search_path = public as $$
  update public.profiles
     set credits = credits - 1, updated_at = now()
   where user_id = p_user
     and credits > 0
     and subscription_status in ('active', 'trialing')
  returning credits;
$$;

-- Give a credit back when the upstream Anthropic call failed. Capped at the limit.
create or replace function public.refund_credit(p_user uuid) returns integer
language sql security definer set search_path = public as $$
  update public.profiles
     set credits = least(credits + 1, credits_limit), updated_at = now()
   where user_id = p_user
  returning credits;
$$;

-- Webhook idempotency: Stripe retries events, a replayed invoice.paid must not
-- reset a balance a second time.
create table public.stripe_events (
  id text primary key,
  received_at timestamptz not null default now()
);
alter table public.stripe_events enable row level security;

revoke execute on function public.consume_credit(uuid) from public, anon, authenticated;
revoke execute on function public.refund_credit(uuid) from public, anon, authenticated;
grant execute on function public.consume_credit(uuid) to service_role;
grant execute on function public.refund_credit(uuid) to service_role;
