import { describe, expect, it } from 'vitest';
import request from 'supertest';
import { createApp } from '../src/app.js';

describe('GET /', () => {
  it("répond 200 et affiche le message d'accueil", async () => {
    const response = await request(createApp()).get('/');

    expect(response.status).toBe(200);
    expect(response.text).toContain('EcoRide V2 OK');
  });
});
