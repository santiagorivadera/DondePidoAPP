import assert from 'node:assert/strict'

export async function testFeatured({ request, appOrigin, onboarding, ownerMfa, adminMfa, business, png }) {
  const endpoint = appOrigin + '/api/featured'
  async function api(account, body, status = 200) {
    const result = await request(endpoint, { body, token: account?.token })
    const payload = await result.json()
    assert.equal(result.status, status, payload.error?.message ?? body?.action)
    return payload.data
  }
  const publicBanner = async (id) => (await api()).banners.find((item) => item.id === id)
  const input = {
    action: 'admin.create', businessId: business.id, title: 'Promoción ficticia de portada',
    mimeType: 'image/png', base64: png, position: 1, enabled: true,
  }
  await api(ownerMfa, input, 403)
  const { id } = await api(adminMfa, input)
  const banner = await publicBanner(id)
  assert.equal(banner?.business_id, business.id)
  assert.equal(banner.title, input.title)
  const imageUrl = new URL(banner.image_url, appOrigin)
  assert.equal(imageUrl.origin, appOrigin)
  const image = await request(imageUrl)
  assert.equal(image.status, 200)
  assert.equal(image.headers.get('content-type'), 'image/png')
  assert.equal(Buffer.from(await image.arrayBuffer()).toString('base64'), png)

  const catalog = await request(appOrigin + '/api/market', {
    body: { action: 'browse', businessId: business.id },
  })
  assert.equal(catalog.status, 200)
  assert.deepEqual((await catalog.json()).data.businesses.map((item) => item.id), [business.id])
  assert.ok((await api(adminMfa, { action: 'admin.list' })).banners.some((item) => item.id === id))

  const hidden = await onboarding(adminMfa, 'business.controls', {
    businessId: business.id, expectedVersion: business.control_version, hidden: true,
  })
  assert.equal(await publicBanner(id), undefined)
  assert.equal((await request(imageUrl)).status, 404)
  await onboarding(adminMfa, 'business.controls', {
    businessId: business.id, expectedVersion: hidden.control_version, hidden: false,
  })
  await api(adminMfa, { action: 'admin.update', id, startsAt: new Date(Date.now() + 86_400_000).toISOString() })
  assert.equal(await publicBanner(id), undefined)
  assert.equal((await request(imageUrl)).status, 404)
  await api(adminMfa, { action: 'admin.update', id, startsAt: null })
  assert.equal((await publicBanner(id)).id, id)
  await api(adminMfa, { action: 'admin.update', id, enabled: false })
  assert.equal(await publicBanner(id), undefined)
  assert.equal((await request(imageUrl)).status, 404)
  console.log('PASS: promoción destacada, imagen, catálogo exacto, aislamiento, vigencia y desactivación')
}
