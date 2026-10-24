// Stripe -> credits. Deploy with --no-verify-jwt (Stripe has no Supabase JWT);
// authenticity comes from the Stripe signature check below.
import Stripe from 'npm:stripe@17';
import { admin, json } from '../_shared/auth.ts';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!);
const cryptoProvider = Stripe.createSubtleCryptoProvider();
const PLAN_CREDITS = Number(Deno.env.get('PLAN_CREDITS') ?? '1000');

const toIso = (sec?: number | null) => (sec ? new Date(sec * 1000).toISOString() : null);

async function userIdForSubscription(subId: string, customerId?: string | null) {
  const sub = await stripe.subscriptions.retrieve(subId);
  if (sub.metadata?.user_id) return { userId: sub.metadata.user_id, sub };
  if (customerId) {
    const { data } = await admin.from('profiles').select('user_id').eq('stripe_customer_id', customerId).maybeSingle();
    if (data) return { userId: data.user_id as string, sub };
  }
  return { userId: null, sub };
}

Deno.serve(async (req) => {
  const sig = req.headers.get('stripe-signature');
  if (!sig) return json({ error: 'no_signature' }, 400);
  const raw = await req.text();

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      raw, sig, Deno.env.get('STRIPE_WEBHOOK_SECRET')!, undefined, cryptoProvider,
    );
  } catch {
    return json({ error: 'bad_signature' }, 400);
  }

  // Idempotency: a replayed event must not reset a balance twice.
  const { error: dup } = await admin.from('stripe_events').insert({ id: event.id });
  if (dup) return json({ received: true, duplicate: true });

  try {
    switch (event.type) {
      case 'checkout.session.completed': {
        const s = event.data.object as Stripe.Checkout.Session;
        if (s.client_reference_id && s.customer) {
          await admin.from('profiles').update({
            stripe_customer_id: s.customer as string,
            stripe_subscription_id: (s.subscription as string) ?? null,
            updated_at: new Date().toISOString(),
          }).eq('user_id', s.client_reference_id);
        }
        break;
      }
      case 'invoice.paid': {
        // A paid invoice = a new billing period: refill to the plan size.
        const inv = event.data.object as Stripe.Invoice & {
          subscription?: string | null;
          parent?: { subscription_details?: { subscription?: string } } | null;
        };
        const subId = inv.subscription ?? inv.parent?.subscription_details?.subscription;
        if (!subId) break;
        const { userId, sub } = await userIdForSubscription(subId, inv.customer as string);
        if (!userId) throw new Error('no_user_for_subscription');
        await admin.from('profiles').update({
          credits: PLAN_CREDITS,
          credits_limit: PLAN_CREDITS,
          subscription_status: 'active',
          stripe_customer_id: inv.customer as string,
          stripe_subscription_id: sub.id,
          current_period_end: toIso(sub.current_period_end ?? sub.items.data[0]?.current_period_end),
          updated_at: new Date().toISOString(),
        }).eq('user_id', userId);
        break;
      }
      case 'customer.subscription.updated':
      case 'customer.subscription.deleted': {
        const sub = event.data.object as Stripe.Subscription;
        const userId = sub.metadata?.user_id;
        if (!userId) break;
        const ended = event.type === 'customer.subscription.deleted';
        await admin.from('profiles').update({
          subscription_status: ended ? 'canceled' : sub.status,
          current_period_end: toIso(sub.current_period_end ?? sub.items.data[0]?.current_period_end),
          ...(ended ? { credits: 0 } : {}),
          updated_at: new Date().toISOString(),
        }).eq('user_id', userId);
        break;
      }
    }
  } catch (err) {
    console.error('webhook failed:', (err as Error).message);
    // Let Stripe retry: forget the event so the retry isn't dropped as a duplicate.
    await admin.from('stripe_events').delete().eq('id', event.id);
    return json({ error: 'handler_failed' }, 500);
  }
  return json({ received: true });
});
