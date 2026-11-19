const plans = {
  single: { label: '1 Mac', price: '$2.49' },
  two: { label: '2 Macs', price: '$4.99' },
  five: { label: '5 Macs', price: '$9.99' },
} as const

type WaitlistPlan = keyof typeof plans
type Environment = Record<string, string | undefined>

export type WaitlistResult = { status: number; body: { message: string } }

export async function joinWaitlist(input: unknown, environment: Environment, request = fetch): Promise<WaitlistResult> {
  if (!input || typeof input !== 'object') return failure(400, 'Enter your email to join the waitlist.')
  const values = input as Record<string, unknown>
  if (values.website) return success()
  const email = typeof values.email === 'string' ? values.email.trim().toLowerCase() : ''
  const name = typeof values.name === 'string' ? values.name.trim().slice(0, 80) : ''
  const plan = typeof values.plan === 'string' && values.plan in plans ? values.plan as WaitlistPlan : 'two'
  if (values.consent !== 'yes') return failure(400, 'Please agree to receive Parcel launch email.')
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) return failure(400, 'Enter a valid email address.')

  const apiKey = environment.RESEND_API_KEY
  const from = environment.RESEND_FROM
  if (!apiKey || !from) return failure(503, 'The waitlist is being connected. Please try again shortly.')
  const headers = { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' }
  const contact = await request('https://api.resend.com/contacts', {
    method: 'POST', headers,
    body: JSON.stringify({ email, first_name: name || undefined, unsubscribed: false, properties: { parcel_plan: plan } }),
  })
  if (!contact.ok && contact.status !== 409) return failure(502, 'We could not save your place. Please try again.')

  const choice = plans[plan]
  const idempotency = await digest(`${email}:${plan}`)
  const emailResponse = await request('https://api.resend.com/emails', {
    method: 'POST',
    headers: { ...headers, 'Idempotency-Key': `parcel-waitlist-${idempotency}` },
    body: JSON.stringify({
      from,
      to: [email],
      reply_to: environment.RESEND_REPLY_TO || undefined,
      subject: 'You are on the Parcel waitlist',
      html: confirmationEmail(name, choice.label, choice.price),
    }),
  })
  return emailResponse.ok ? success() : failure(502, 'Your place was saved, but the confirmation email could not be sent. Please try again.')
}

function confirmationEmail(name: string, macs: string, price: string) {
  const greeting = name ? `Hi ${escapeHtml(name)},` : 'Hi,'
  return `<div style="font-family:-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif;max-width:560px;margin:auto;padding:32px;color:#25251f"><h1 style="font-size:32px;letter-spacing:-1.4px">You are on the Parcel waitlist.</h1><p>${greeting}</p><p>Thanks for joining. You chose the <strong>${macs} licence at ${price}</strong>. We will email you when Parcel is ready.</p><p>Parcel gives your Mac one calm place for files, clipboard items, conversions and quick handoffs.</p><p style="margin-top:30px;color:#737264">— Parcel</p></div>`
}

function escapeHtml(value: string) {
  return value.replace(/[&<>'"]/g, character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' })[character]!)
}

async function digest(value: string) {
  const data = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return Array.from(new Uint8Array(data)).slice(0, 12).map(byte => byte.toString(16).padStart(2, '0')).join('')
}

function success(): WaitlistResult { return { status: 200, body: { message: 'You are on the Parcel waitlist.' } } }
function failure(status: number, message: string): WaitlistResult { return { status, body: { message } } }
