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
    const { data: tokens, error } = await supabase.from('device_tokens').select('token').eq('user_id', userId).eq('platform', 'ios');
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
    const host = APNS_PRODUCTION ? 'api.push.apple.com' : 'api.sandbox.push.apple.com';
    const results = await Promise.allSettled(tokens.map(({ token })=>fetch(`https://${host}/3/device/${token}`, {
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
      })));
    const sent = results.filter((r)=>r.status === 'fulfilled').length;
    return new Response(JSON.stringify({
      sent
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
