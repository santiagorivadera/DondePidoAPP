import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { mkdirSync, writeFileSync } from 'node:fs'
import { createHmac, randomUUID } from 'node:crypto'
import { setTimeout as delay } from 'node:timers/promises'
import { fileURLToPath } from 'node:url'
import { testMarket } from './market-flow.mjs'
import { testFeatured } from './featured-flow.mjs'

const authOrigin = 'http://127.0.0.1:55421'
const mailOrigin = 'http://127.0.0.1:55424'
const projectRoot = fileURLToPath(new URL('../', import.meta.url))
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aVnQAAAAASUVORK5CYII='

function appOriginFromEnv() {
  const url = new URL(process.env.DONDEP_E2E_APP_URL ?? 'http://127.0.0.1:3000')
  assert.ok(
    url.protocol === 'http:' && ['127.0.0.1', 'localhost'].includes(url.hostname)
      && !url.username && !url.password && url.pathname === '/' && !url.search && !url.hash,
    'DONDEP_E2E_APP_URL must be a local HTTP origin',
  )
  return url.origin
}

function runSupabase(args) {
  return execFileSync('supabase', args, {
    cwd: projectRoot,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    timeout: 15000,
  })
}

function localSql(sql) {
  return runSupabase(['db', 'query', '--local', '--output-format', 'json', sql])
}

function localRows(sql) {
  return JSON.parse(localSql(sql)).rows
}

function checkedId(id, description) {
  assert.ok(typeof id === 'string' && uuidPattern.test(id), description)
  return id
}

async function request(url, { token, body, apiKey, redirect = 'error' } = {}) {
  const headers = new Headers()
  if (apiKey) headers.set('apikey', apiKey)
  if (token) headers.set('authorization', 'Bearer ' + token)
  if (body !== undefined) headers.set('content-type', 'application/json')
  return fetch(url, {
    headers,
    method: body === undefined ? 'GET' : 'POST',
    body: body === undefined ? undefined : JSON.stringify(body),
    redirect,
    signal: AbortSignal.timeout(10000),
  })
}

async function mailboxMessage(query, matches) {
  const search = new URL('/api/v1/search', mailOrigin)
  search.searchParams.set('query', query)

  for (let attempt = 0; attempt < 40; attempt += 1) {
    const result = await request(search)
    assert.ok(result.ok, 'Mailpit search failed with HTTP ' + result.status)
    const { messages = [] } = await result.json()
    const match = messages.find(matches)
    if (match) {
      const message = await request(mailOrigin + '/api/v1/message/' + encodeURIComponent(match.ID))
      assert.ok(message.ok, 'Mailpit message lookup failed with HTTP ' + message.status)
      return message.json()
    }
    await delay(250)
  }
  throw new Error('Timed out waiting for the expected local Mailpit message')
}

async function confirmEmail(email) {
  const message = await mailboxMessage('to:' + email, () => true)
  const link = (message.HTML ?? '').match(/href="([^"]+\/auth\/v1\/verify\?[^"]+)"/i)
  assert.ok(link, 'Mailpit did not capture an Auth confirmation link')
  const url = new URL(link[1].replaceAll('&amp;', '&'))
  assert.ok(
    url.protocol === 'http:' && ['127.0.0.1', 'localhost'].includes(url.hostname)
      && url.port === '55421' && url.pathname === '/auth/v1/verify'
      && !url.username && !url.password,
    'Email confirmation link must target the local Auth service',
  )

  const result = await request(url, { redirect: 'manual' })
  assert.ok([302, 303].includes(result.status), 'Auth did not redirect after confirmation')
  const location = new URL(result.headers.get('location'), url)
  assert.ok(!location.searchParams.has('error') && !new URLSearchParams(location.hash.slice(1)).has('error'),
    'Auth rejected the email confirmation')
}

function totp(secret) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'
  const key = []
  let bits = 0
  let value = 0
  for (const letter of secret.toUpperCase().replace(/=+$/, '')) {
    const digit = alphabet.indexOf(letter)
    assert.ok(digit >= 0, 'Auth returned an invalid Base32 TOTP secret')
    value = (value << 5) | digit
    bits += 5
    if (bits >= 8) {
      bits -= 8
      key.push((value >> bits) & 0xff)
    }
  }

  const counter = Buffer.alloc(8)
  counter.writeBigUInt64BE(BigInt(Math.floor(Date.now() / 30000)))
  const hash = createHmac('sha1', Buffer.from(key)).update(counter).digest()
  const offset = hash.at(-1) & 0x0f
  return String((hash.readUInt32BE(offset) & 0x7fffffff) % 1000000).padStart(6, '0')
}

async function run() {
  const appOrigin = appOriginFromEnv()
  const status = JSON.parse(runSupabase(['status', '--output', 'json']))
  const apiKey = status.PUBLISHABLE_KEY ?? status.ANON_KEY
  assert.ok(apiKey, 'The local Supabase stack must expose a publishable or anon key')

  async function auth(path, body, token) {
    const result = await request(authOrigin + '/auth/v1' + path, { apiKey, body, token })
    assert.ok(result.ok, 'Local Auth ' + path + ' returned HTTP ' + result.status)
    return result.json()
  }

  function fixtureEmail(role) {
    return 'onboarding-' + role + '-' + randomUUID() + '@example.invalid'
  }

  async function createAccount(email) {
    const password = 'LocalOnly!' + randomUUID()
    await auth('/signup', { email, password })
    await confirmEmail(email)
    const session = await auth('/token?grant_type=password', { email, password })
    assert.ok(session.user?.email_confirmed_at, 'Password session requires a confirmed email')
    assert.ok(session.access_token, 'Auth did not return an access token')
    return { id: checkedId(session.user.id, 'Invalid local Auth user ID'), token: session.access_token, session }
  }

  async function enrollMfa(account) {
    const factor = await auth('/factors', { factor_type: 'totp' }, account.token)
    const factorPath = '/factors/' + checkedId(factor.id, 'Invalid Auth factor ID')
    const challenge = await auth(factorPath + '/challenge', {}, account.token)
    assert.ok(factor.totp?.secret, 'Auth did not return a TOTP secret')
    const session = await auth(factorPath + '/verify', {
      challenge_id: challenge.id,
      code: totp(factor.totp.secret),
    }, account.token)
    assert.ok(session.access_token, 'MFA did not return a reinforced access token')
    return { ...account, token: session.access_token, session }
  }

  async function onboarding(account, action, fields = {}, expected = [200]) {
    const result = await request(appOrigin + '/api/onboarding', {
      token: account?.token,
      body: { action, ...fields },
    })
    assert.ok(expected.includes(result.status), action + ' returned HTTP ' + result.status)
    if (result.ok) {
      const payload = await result.json()
      assert.ok(Object.hasOwn(payload, 'data'), action + ' did not return data')
      return payload.data
    }
  }

  async function issueChallenge(account, phone) {
    const challengeId = checkedId(
      await onboarding(account, 'phone.issue', { phone }),
      'Invalid local SMS challenge ID',
    )
    const message = await mailboxMessage(
      'to:sms-local@example.invalid subject:' + challengeId,
      (candidate) => candidate.Subject === 'DondePido SMS local ' + challengeId,
    )
    const code = (message.Text ?? '').match(/C[oó]digo:\s*(\d{6})\b/i)?.[1]
    assert.ok(code, 'Mailpit did not capture the local SMS verification code')
    return { phone, challengeId, code }
  }

  const reference = await onboarding(null, 'reference')
  const cityId = checkedId(reference.cities.find((city) => city.slug === 'dean-funes')?.id,
    'The local reference seed must include Deán Funes')
  assert.ok(reference.sectors.some((sector) => sector.code === 'kioscos'),
    'The public reference must include the kiosk sector')

  const ownerEmail = fixtureEmail('owner')
  const application = {
    email: ownerEmail,
    sector: 'kioscos',
    observation: 'Local ficticio para el ensayo de alta comercial.',
  }
  assert.equal(await onboarding(null, 'application.request', application), null,
    'The public application response must not expose an application ID')
  assert.equal(await onboarding(null, 'application.request', application), null,
    'Repeating a public application must have the same generic response')

  const owner = await createAccount(ownerEmail)
  const other = await createAccount(fixtureEmail('other'))
  const admin = await createAccount(fixtureEmail('admin'))
  localSql("insert into dondepido.admin_roles (user_id) values ('" + admin.id + "');")

  try {
    const candidates = localRows(
      "select candidate.phone from (select '+120255501' || lpad(n::text, 2, '0') as phone"
        + " from generate_series(0, 99) n) candidate"
        + " where not exists (select 1 from dondepido.verified_phones p where p.phone_e164 = candidate.phone)"
        + " order by random() limit 2;",
    )
    assert.equal(candidates.length, 2, 'The local reserved test phone pool is exhausted')

    await onboarding(null, 'profile', { firstName: 'Prueba', lastName: 'Local' }, [401])
    await onboarding(owner, 'profile', { firstName: 'Titular', lastName: 'Local' })
    await onboarding(other, 'profile', { firstName: 'Otra', lastName: 'Cuenta' })
    assert.deepEqual(await onboarding(owner, 'profile.mine'), {
      profile: { firstName: 'Titular', lastName: 'Local' }, phone: null,
    })

    const ownerChallenge = await issueChallenge(owner, candidates[0].phone)
    await onboarding(other, 'phone.verify', ownerChallenge, [400])
    assert.equal(await onboarding(owner, 'phone.verify', ownerChallenge), 'verified')
    assert.equal((await onboarding(owner, 'profile.mine')).phone, candidates[0].phone)
    assert.equal((await onboarding(other, 'profile.mine')).phone, null)
    await onboarding(owner, 'phone.verify', ownerChallenge, [410])

    const formattedDuplicate = '+1 (202) 555-01' + candidates[0].phone.slice(-2)
    const duplicateChallenge = await issueChallenge(other, formattedDuplicate)
    await onboarding(other, 'phone.verify', duplicateChallenge, [409])

    // Advance only the test challenge timestamps to avoid waiting for the real cooldown.
    localSql("update dondepido.phone_challenges set issued_at = now() - interval '61 seconds'"
      + " where id = '" + duplicateChallenge.challengeId + "';")
    const expiredChallenge = await issueChallenge(other, candidates[1].phone)
    localSql("update dondepido.phone_challenges set issued_at = now() - interval '11 minutes',"
      + " expires_at = now() - interval '1 minute' where id = '" + expiredChallenge.challengeId + "';")
    await onboarding(other, 'phone.verify', expiredChallenge, [410])
    await onboarding(other, 'phone.verify', await issueChallenge(other, candidates[1].phone))

    const pending = await onboarding(owner, 'application.mine')
    assert.equal(pending.length, 1, 'The applicant must recover one application after a public retry')
    assert.equal(pending[0].status, 'pending', 'The applicant must recover their pending application')
    const applicationId = checkedId(pending[0].id, 'Invalid commercial application ID')
    const otherApplications = await onboarding(other, 'application.mine')
    assert.ok(otherApplications.every((item) => item.id !== applicationId),
      'Another applicant must not see the pending application')

    const approval = { applicationId, decision: 'approved', cityId, reason: 'Aprobación de prueba local' }
    await onboarding(other, 'application.decide', approval, [403])
    await onboarding(admin, 'application.decide', approval, [403])
    const adminMfa = await enrollMfa(admin)
    const inbox = await onboarding(adminMfa, 'application.inbox')
    assert.ok(inbox.some((item) => item.id === applicationId && item.status === 'pending'),
      'The reinforced administrator must see the pending application')
    await onboarding(adminMfa, 'application.decide', approval)

    const logo = await onboarding(owner, 'logo.upload', { mimeType: 'image/png', base64: png })
    assert.ok(typeof logo === 'string' && logo.length > 0, 'Logo upload did not return an object key')
    const completion = { applicationId, name: 'Kiosco ficticio E2E', address: 'Calle de prueba 100', logo }
    const otherLogo = await onboarding(other, 'logo.upload', { mimeType: 'image/png', base64: png })
    await onboarding(owner, 'application.complete', { ...completion, logo: otherLogo }, [400])
    await onboarding(other, 'application.complete', { ...completion, logo: otherLogo }, [404])
    const businessId = checkedId(await onboarding(owner, 'application.complete', completion), 'Invalid business ID')
    assert.equal(await onboarding(owner, 'application.complete', completion), businessId,
      'Replaying the commercial registration must return the same business')

    const publication = { businessId, pickup: true, delivery: false, confirmPublicContact: true }
    await onboarding(owner, 'business.publish', publication, [403])
    const otherMfa = await enrollMfa(other)
    await onboarding(otherMfa, 'business.publish', publication, [403])
    assert.deepEqual(await onboarding(otherMfa, 'business.mine'), [],
      'A reinforced session still cannot see businesses without a membership')
    const ownerMfa = await enrollMfa(owner)
    const owned = await onboarding(ownerMfa, 'business.mine')
    assert.equal(owned.length, 1, 'A repeated registration must create one owner membership')
    assert.equal(owned[0].id, businessId)
    assert.equal(owned[0].publication_status, 'draft', 'Completing a registration must not publish the business')
    await onboarding(ownerMfa, 'business.publish', publication, [409])

    const hours = { businessId, hours: [{ weekday: 1, intervals: [[540, 780], [960, 1200]] }] }
    await onboarding(owner, 'business.hours', hours, [403])
    await onboarding(ownerMfa, 'business.hours', hours)
    await onboarding(ownerMfa, 'business.hours', hours)
    const weekly = localRows(
      "select weekday, opening_minutes::text as intervals from dondepido.business_weekly_hours"
        + " where business_id = '" + businessId + "';",
    )
    assert.deepEqual(weekly, [{ weekday: 1, intervals: '{[540,780),[960,1200)}' }],
      'Repeating the hours update must retain one schedule for the local day')

    await onboarding(ownerMfa, 'business.publish', publication)

    const [published] = await onboarding(ownerMfa, 'business.mine')
    assert.equal(published.publication_status, 'published')
    assert.equal(published.offers_pickup, true)
    assert.equal(published.offers_delivery, false)
    console.log('PASS: local signup, phone verification, commercial approval, idempotent registration and publication')
    if (process.argv.includes('--market')) {
      const market = async (account, action, fields = {}, expected = 200) => {
        const result = await request(appOrigin + '/api/market', {
          token: account?.token,
          body: { action, ...fields },
        })
        const payload = await result.json()
        assert.equal(result.status, expected, `${fields.operation ?? action}: ${payload.error?.code ?? 'respuesta'}`)
        return payload.data
      }
      const noticeCount = (id) => localRows(
        "select count(*)::integer as count from dondepido.order_notice_outbox where order_id = '"
          + checkedId(id, 'Invalid local order ID') + "';",
      )[0].count
      const dispatchNotice = (id) => execFileSync(process.execPath, [
        'scripts/dispatch-notices-local.mjs', '--order', checkedId(id, 'Invalid local order ID'),
      ], { cwd: projectRoot, encoding: 'utf8', timeout: 30_000 }).trim()
      const verifyNotice = async (id) => {
        const mismatch = execFileSync('docker', [
          'exec', '-i', 'supabase_db_dondepido-local', 'psql', '-X', '-U', 'supabase_admin',
          '-d', 'postgres', '-Atq', '-v', 'ON_ERROR_STOP=1',
        ], {
          input: "set role dondepido_notice_dispatcher; select dondepido.claim_test_notice('"
            + checkedId(id, 'Invalid local order ID') + "', '+19999999999')->>'status';",
          encoding: 'utf8', timeout: 10_000,
        }).trim()
        assert.equal(mismatch, 'empty')
        assert.match(dispatchNotice(id), /Capturados: 1/)
        const subject = 'DondePido WhatsApp local ' + id
        const message = await mailboxMessage(
          'to:whatsapp-local@example.invalid subject:' + id,
          (candidate) => candidate.Subject === subject,
        )
        assert.match(dispatchNotice(id), /Capturados: 0/)
        return message.Text
      }
      const demo = await testMarket({ market, onboarding, ownerMfa, buyer: other, adminMfa, businessId, cityId, logo, noticeCount, verifyNotice })
      if (process.argv.includes('--mobile-fixtures')) {
        const fixture = (account, aal) => ({
          access_token: account.token, refresh_token: account.session.refresh_token,
          expires_at: Math.floor(Date.now() / 1000) + account.session.expires_in,
          email: account.session.user.email, aal, recovery: false,
        })
        const dir = new URL('../.playwright-cli/', import.meta.url)
        mkdirSync(dir, { recursive: true })
        writeFileSync(new URL('demo-fixtures.json', dir), JSON.stringify({
          appOrigin, ...demo, buyer: fixture(other, 'aal1'), owner: fixture(ownerMfa, 'aal2'),
        }), { flag: 'wx' })
      }
    }
    if (process.argv.includes('--featured')) {
      await testFeatured({ request, appOrigin, onboarding, ownerMfa, adminMfa, business: published, png })
    }
  } finally {
    localSql("delete from dondepido.admin_roles where user_id = '" + admin.id + "';")
  }
}

try {
  await run()
} catch (error) {
  console.error('FAIL: ' + error.message)
  process.exitCode = 1
}
