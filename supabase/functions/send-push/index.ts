import { createClient } from 'npm:@supabase/supabase-js@2';
const APNS_KEY_ID = Deno.env.get('APNS_KEY_ID');
const APNS_TEAM_ID = Deno.env.get('APNS_TEAM_ID');
const APNS_PRIVATE_KEY = Deno.env.get('APNS_PRIVATE_KEY');
const APNS_BUNDLE_ID = Deno.env.get('APNS_BUNDLE_ID');
const APNS_PRODUCTION = Deno.env.get('APNS_PRODUCTION') === 'true';
async function generateAPNsJWT() {
  const pem = APNS_PRIVATE_KEY.replace(/\\n/g, '\n');
  const pemBody = pem.replace('-----BEGIN PRIVATE KEY-----', '').replace('-----END PRIVATE KEY-----', '').replace(/\s/g, '');
  const keyBytes = Uint8Array.from(atob(pemBody), (c)=>c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey('pkcs8', keyBytes, {
    name: 'ECDSA',
    namedCurve: 'P-256'
  }, false, [
    'sign'
  ]);
  const now = Math.floor(Date.now() / 1000);
  const encode = (obj)=>btoa(JSON.stringify(obj)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
  const header = {
    alg: 'ES256',
    kid: APNS_KEY_ID
  };
  const payload = {
    iss: APNS_TEAM_ID,
    iat: now
  };
  const signingInput = `${encode(header)}.${encode(payload)}`;
  const signature = await crypto.subtle.sign({
    name: 'ECDSA',
    hash: 'SHA-256'
  }, cryptoKey, new TextEncoder().encode(signingInput));
  const sigBase64 = btoa(String.fromCharCode(...new Uint8Array(signature))).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
  return `${signingInput}.${sigBase64}`;
}
Deno.serve(async (req)=>{
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'authorization, apikey, content-type'
      }
    });
  }
  try {
    const { userId, title, body, data = {} } = await req.json();
    const supabase = createClient(Deno.env.get('SUPABASE_URL'), Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'));
    const { data: tokens, error } = await supabase.from('device_tokens').select('id, token, environment').eq('user_id', userId).eq('platform', 'ios');
    if (error || !tokens?.length) {
      return new Response(JSON.stringify({
        sent: 0
      }), {
        headers: {
          'Content-Type': 'application/json'
        }
      });
    }
    const jwt = await generateAPNsJWT();
    // Choose the gateway per token. APNs tokens are environment-specific: a
    // sandbox token sent to the production gateway (or vice versa) is rejected
    // with BadDeviceToken. A single global APNS_PRODUCTION flag therefore broke
    // whichever half of the devices it did not match. Fall back to the flag only
    // for rows predating the environment column.
    const gatewayFor = (environment)=>{
      const env = environment ?? (APNS_PRODUCTION ? 'production' : 'sandbox');
      return env === 'sandbox' ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
    };
    // Tokens APNs tells us are permanently invalid, collected for pruning below.
    const dead = [];
    const results = await Promise.allSettled(tokens.map(async ({ id, token, environment })=>{
      const res = await fetch(`https://${gatewayFor(environment)}/3/device/${token}`, {
        method: 'POST',
        headers: {
          'authorization': `bearer ${jwt}`,
          'apns-topic': APNS_BUNDLE_ID,
          'apns-push-type': 'alert',
          'content-type': 'application/json'
        },
        body: JSON.stringify({
          aps: {
            alert: {
              title,
              body
            },
            sound: 'default',
            badge: 1
          },
          ...data
        })
      });
      // A rejected push still resolves the fetch, so the old
      // `status === 'fulfilled'` count reported success for every failure —
      // which is why broken delivery went unnoticed. Surface APNs' verdict.
      if (!res.ok) {
        const reason = await res.text().catch(()=>'');
        // BadDeviceToken and Unregistered are permanent, not transient: the token
        // will never be valid again. Apple's guidance is to stop using it. Without
        // pruning, a device that reinstalls or moves between debug and TestFlight
        // builds leaves rows that are retried on every push forever.
        if (res.status === 410 || reason.includes('BadDeviceToken') || reason.includes('Unregistered')) {
          dead.push(id);
        }
        throw new Error(`APNs ${res.status} ${reason} (env=${environment ?? 'unknown'})`);
      }
      return true;
    }));

    // Self-heal: drop the permanently dead tokens so the table stays honest.
    let pruned = 0;
    if (dead.length) {
      const { error: pruneError } = await supabase.from('device_tokens').delete().in('id', dead);
      if (pruneError) {
        console.error('[send-push] prune failed:', pruneError.message);
      } else {
        pruned = dead.length;
        console.log(`[send-push] pruned ${pruned} dead token(s)`);
      }
    }
    const sent = results.filter((r)=>r.status === 'fulfilled').length;
    const failures = results.filter((r)=>r.status === 'rejected').map((r)=>String(r.reason?.message ?? r.reason));
    if (failures.length) console.error('[send-push] failures:', failures);
    // Report failures too, so a caller (and the function logs) can tell the
    // difference between "nobody to notify" and "every push was rejected".
    return new Response(JSON.stringify({
      sent,
      failed: failures.length,
      pruned,
      errors: failures
    }), {
      headers: {
        'Content-Type': 'application/json'
      }
    });
  } catch (err) {
    return new Response(JSON.stringify({
      error: String(err)
    }), {
      status: 500,
      headers: {
        'Content-Type': 'application/json'
      }
    });
  }
});
