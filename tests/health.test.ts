import { beforeEach, describe, expect, it, vi } from 'vitest';
import request from 'supertest';

// Les deux services sont remplacés par des doublures (mocks) : le test
// vérifie la RÈGLE de code HTTP, pas l'état réel des bases de la machine.
// Sans ça, le test passerait pour une mauvaise raison — parce que MySQL
// se trouve être éteint — et deviendrait rouge le jour où il tourne.
vi.mock('../src/services/mysql.service.js', () => ({
  pingMysql: vi.fn(),
  getPool: vi.fn(),
  closePool: vi.fn(),
}));
vi.mock('../src/services/mongo.service.js', () => ({
  pingMongo: vi.fn(),
  getDb: vi.fn(),
  closeMongo: vi.fn(),
}));

const { pingMysql } = await import('../src/services/mysql.service.js');
const { pingMongo } = await import('../src/services/mongo.service.js');
const { createApp } = await import('../src/app.js');

const mockedPingMysql = vi.mocked(pingMysql);
const mockedPingMongo = vi.mocked(pingMongo);

describe('GET /health — asymétrie MySQL / Mongo', () => {
  beforeEach(() => {
    vi.resetAllMocks();
  });

  it('200 quand les deux bases répondent', async () => {
    mockedPingMysql.mockResolvedValue(true);
    mockedPingMongo.mockResolvedValue(true);

    const response = await request(createApp()).get('/health');

    expect(response.status).toBe(200);
    expect(response.body).toEqual({
      status: 'ok',
      services: { mysql: true, mongo: true },
      degraded: false,
    });
  });

  it('200 + degraded quand seul Mongo est absent (préférences manquantes)', async () => {
    mockedPingMysql.mockResolvedValue(true);
    mockedPingMongo.mockResolvedValue(false);

    const response = await request(createApp()).get('/health');

    expect(response.status).toBe(200);
    expect(response.body.status).toBe('ok');
    expect(response.body.degraded).toBe(true);
  });

  it('503 quand MySQL est absent : ni comptes ni trajets, rien à servir', async () => {
    mockedPingMysql.mockResolvedValue(false);
    mockedPingMongo.mockResolvedValue(true);

    const response = await request(createApp()).get('/health');

    expect(response.status).toBe(503);
    expect(response.body.status).toBe('unavailable');
  });

  it("503 quand les deux sont absentes, et degraded reste false : l'app est hors service, pas dégradée", async () => {
    mockedPingMysql.mockResolvedValue(false);
    mockedPingMongo.mockResolvedValue(false);

    const response = await request(createApp()).get('/health');

    expect(response.status).toBe(503);
    expect(response.body.degraded).toBe(false);
  });
});
