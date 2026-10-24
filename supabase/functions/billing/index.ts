// POST /billing  { action: 'checkout' | 'portal' }  ->  { url }
import Stripe from 'npm:stripe@17';
import { admin, getUser, json } from '../_shared/auth.ts';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!);
const SITE = Deno.env.get('SITE_URL') ?? 'https://permylast.app';

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
  const user = await getUser(req);
  if (!user) return json({ error: 'unauthorized' }, 401);

  let action = 'checkout';
  try { action = (await req.json()).action ?? 'checkout'; } catch { /* default */ }

  const { data: profile } = await admin
    .from('profiles').select('stripe_customer_id, subscription_status')
    .eq('user_id', user.id).single();

  if (action === 'portal') {
    if (!profile?.stripe_customer_id) return json({ error: 'no_customer' }, 400);
    const portal = await stripe.billingPortal.sessions.create({
      customer: profile.stripe_customer_id,
      return_url: `${SITE}/account.html`,
    });
    return json({ url: portal.url });
  }

  if (profile && ['active', 'trialing'].includes(profile.subscription_status)) {
    return json({ error: 'already_subscribed' }, 409);
  }

  const session = await stripe.checkout.sessions.create({
    mode: 'subscription',
    line_items: [{ price: Deno.env.get('STRIPE_PRICE_ID')!, quantity: 1 }],
    client_reference_id: user.id,
    ...(profile?.stripe_customer_id
      ? { customer: profile.stripe_customer_id }
      : { customer_email: user.email }),
    // The webhook resolves the user from subscription metadata, so it works
    // even if invoice.paid arrives before checkout.session.completed.
    subscription_data: { metadata: { user_id: user.id } },
    success_url: `${SITE}/account.html?checkout=success`,
    cancel_url: `${SITE}/account.html?checkout=cancelled`,
  });
  return json({ url: session.url });
});
