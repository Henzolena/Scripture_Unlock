Deno.serve(async (req)=>{
  if (req.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'authorization, apikey, content-type'
      }
    });
  }
  const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY');
  try {
    const { name, partnerEmail, streak, accuracy, totalAnswered } = await req.json();
    const accuracyPct = Math.round((accuracy ?? 0) * 100);
    const streakVal = streak ?? 0;
    const totalVal = totalAnswered ?? 0;
    const html = `
      <!DOCTYPE html>
      <html>
      <body style="margin:0;padding:0;background:#f9f6f0;font-family:Georgia,serif;">
        <div style="max-width:560px;margin:40px auto;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,0.08);">
          <div style="background:linear-gradient(135deg,#0D1B3E,#1E3A5F);padding:32px;">
            <h1 style="margin:0;color:#C9A961;font-size:22px;font-weight:bold;">Scripture Unlock</h1>
            <p style="margin:8px 0 0;color:rgba(255,255,255,0.65);font-size:13px;">Weekly accountability report</p>
          </div>
          <div style="padding:32px;">
            <h2 style="margin:0 0 8px;color:#1a2e5a;font-size:20px;">${name}&apos;s Weekly Report</h2>
            <p style="margin:0 0 24px;color:#718096;font-size:14px;">Here is how ${name} is doing in Scripture Unlock this week.</p>

            <div style="display:flex;gap:16px;margin-bottom:32px;">
              <div style="flex:1;background:#f7f3e9;border-radius:12px;padding:20px;text-align:center;">
                <div style="font-size:40px;font-weight:bold;color:#C9A961;">${streakVal}</div>
                <div style="font-size:12px;color:#718096;margin-top:4px;">Day Streak</div>
              </div>
              <div style="flex:1;background:#f0f4fc;border-radius:12px;padding:20px;text-align:center;">
                <div style="font-size:40px;font-weight:bold;color:#2b4a8a;">${accuracyPct}%</div>
                <div style="font-size:12px;color:#718096;margin-top:4px;">Accuracy</div>
              </div>
              <div style="flex:1;background:#f0f4fc;border-radius:12px;padding:20px;text-align:center;">
                <div style="font-size:40px;font-weight:bold;color:#2b4a8a;">${totalVal}</div>
                <div style="font-size:12px;color:#718096;margin-top:4px;">Verses Answered</div>
              </div>
            </div>

            <hr style="border:none;border-top:1px solid #e8e0d0;margin-bottom:24px;">
            <p style="color:#a0aec0;font-size:12px;margin:0;">You receive this because ${name} added you as their accountability partner in Scripture Unlock.</p>
            <p style="color:#C9A961;font-size:12px;margin:8px 0 0;">&quot;Three verses to unlock the day&quot;</p>
          </div>
        </div>
      </body>
      </html>
    `;
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        from: 'Scripture Unlock <noreply@gorobale.tech>',
        to: partnerEmail,
        subject: `${name}'s weekly Scripture Unlock report`,
        html
      })
    });
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`Resend: ${text}`);
    }
    return new Response(JSON.stringify({
      sent: true
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
