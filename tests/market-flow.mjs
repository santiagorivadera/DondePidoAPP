import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'

export async function testMarket({ market, onboarding, owner, buyer, adminMfa, businessId, cityId, logo, noticeCount, verifyNotice }) {
  const catalog = (account, operation, data, status) => market(account, 'catalog', { operation, ...data }, status)
  const orders = (account, operation, data, status) => market(account, 'orders', { operation, ...data }, status)

  const requestId = await onboarding(owner, 'application.submit', {
    sector: 'gastronomia', observation: 'Segundo comercio ficticio para verificar el carrito.',
  })
  await onboarding(adminMfa, 'application.decide', {
    applicationId: requestId, decision: 'approved', cityId, reason: 'Prueba local',
  })
  const kitchen = await onboarding(owner, 'application.complete', {
    applicationId: requestId, name: 'Rotisería ficticia E2E', address: 'Calle de prueba 200', logo,
  })
  await onboarding(owner, 'business.hours', {
    businessId: kitchen, hours: [{ weekday: 1, intervals: [[540, 780]] }],
  })
  await onboarding(owner, 'business.publish', {
    businessId: kitchen, pickup: true, delivery: true, confirmPublicContact: true,
  })
  for (const id of [businessId, kitchen]) {
    await catalog(owner, 'reception', { businessId: id, acceptingOrders: true })
  }
  await catalog(owner, 'delivery', { businessId: kitchen, deliveryFee: 80000 })

  const label = `Agua demo ${randomUUID().slice(0, 8)}`
  await catalog(adminMfa, 'reference', { name: label, category: 'Bebidas', brand: 'Marca demo', presentation: '500 ml' })
  await catalog(buyer, 'mine', {}, 403)
  await catalog(buyer, 'mine', { businessId }, 403)
  assert.ok((await catalog(adminMfa, 'mine', {})).references.some(item => item.name === label))
  const reference = (await catalog(owner, 'mine', { businessId })).references.find(item => item.name === label)
  assert.ok(reference, 'El producto aprobado debe aparecer para el comercio')
  const variantId = reference.id ?? reference.variant_id
  const kioskInput = { businessId, name: label, category: 'Bebidas', variantId, price: 100000, kind: 'individual' }
  await catalog(owner, 'save', { ...kioskInput, variantId: null }, 400)
  await catalog(owner, 'save', { ...kioskInput, name: label.toUpperCase(), brand: 'Escritura libre' })
  const food = { businessId: kitchen, name: 'Empanada demo', category: 'Comidas', price: 250000, kind: 'individual' }
  await catalog(owner, 'save', food)
  await catalog(owner, 'save', { ...food, name: 'Tarta demo', price: 500000 })
  const { offers } = await catalog(owner, 'mine', { businessId: kitchen })
  const empanada = offers.find(item => item.name === food.name)
  const tarta = offers.find(item => item.name === 'Tarta demo')
  assert.ok(empanada && tarta)
  await catalog(owner, 'discount', { businessId: kitchen, offerId: empanada.id, percent: 20 })
  await catalog(owner, 'save', { ...food, name: 'Combo demo', kind: 'combo', price: 650000,
    components: [{ offerId: empanada.id, quantity: 1 }, { offerId: tarta.id, quantity: 1 }] })
  const search = await market(null, 'browse', { q: label, sector: 'kioscos' })
  const water = search.offers.find(item => item.business_id === businessId)
  assert.ok(water, 'La búsqueda debe devolver la oferta del kiosco')
  assert.equal(Number(water.price), 100000)
  assert.equal(water.name, label)
  assert.equal(water.brand, 'Marca demo')
  const promo = await market(null, 'browse', { q: 'Empanada demo', sector: 'gastronomia' })
  assert.equal(Number(promo.offers.find(item => item.id === empanada.id)?.price), 200000)
  assert.ok(promo.offers.some(item => item.name === 'Combo demo'))

  const items = [{ offerId: water.id, quantity: 1 }, { offerId: empanada.id, quantity: 2 }]
  const fulfillment = [{ businessId, mode: 'pickup' }, {
    businessId: kitchen, mode: 'delivery', address: 'Calle de prueba 300',
  }]
  const quote = await orders(buyer, 'quote', { items, fulfillment })
  assert.equal(Number(quote.total), 580000)
  assert.equal((await orders(buyer, 'consent', { enabled: true })).enabled, true)
  const payload = { quoteToken: quote.quoteToken, idempotencyKey: randomUUID() }
  await orders(owner, 'submit', payload, 404)
  const group = await orders(buyer, 'submit', payload)
  assert.equal(group.orders.length, 2)
  assert.equal((await orders(buyer, 'submit', payload)).groupId, group.groupId)
  await orders(buyer, 'inbox', { businessId }, 403)
  await orders(adminMfa, 'inbox', { businessId }, 403)
  const kioskOrder = (await orders(owner, 'inbox', { businessId })).orders.find(item => item.status === 'received')
  const kitchenOrder = (await orders(owner, 'inbox', { businessId: kitchen })).orders.find(item => item.status === 'received')
  assert.ok(kioskOrder && kitchenOrder)
  await orders(owner, 'decide', { orderId: kioskOrder.id, expectedVersion: kioskOrder.version,
    decision: 'rejected', reason: 'Prueba de rechazo' })
  await orders(owner, 'decide', { orderId: kitchenOrder.id, expectedVersion: kitchenOrder.version, decision: 'confirmed' })
  const history = (await orders(buyer, 'mine', {})).orders
  assert.equal(history.find(item => item.id === kioskOrder.id).status, 'rejected')
  const confirmed = history.find(item => item.id === kitchenOrder.id)
  assert.equal(confirmed.status, 'confirmed')
  assert.equal(noticeCount(kioskOrder.id), 0)
  assert.equal(noticeCount(confirmed.id), 1)
  const notice = await verifyNotice(confirmed.id)
  assert.match(notice, /Calle de prueba 300/)
  assert.match(notice, /Empanada demo/)
  await orders(owner, 'complete', { orderId: confirmed.id, expectedVersion: confirmed.version })
  assert.equal((await orders(buyer, 'mine', {})).orders.find(item => item.id === confirmed.id).status, 'completed')
  await orders(buyer, 'stats', { businessId: kitchen }, 403)
  const stats = await orders(owner, 'stats', { businessId: kitchen })
  assert.equal(stats.counts.confirmed, 1)
  assert.equal(stats.counts.completed, 1)
  assert.equal(stats.counts.rejected, 0)
  assert.equal(stats.peakHour.count, 1)
  console.log('PASS: catálogo, promociones, retiro y entrega, aislamiento, reintento y decisiones independientes')
  return { kiosk: businessId, kitchen, label }
}
