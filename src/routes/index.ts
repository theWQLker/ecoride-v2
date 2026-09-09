import { Router } from 'express';
import { showHome } from '../controllers/home.controller.js';
import { showHealth } from '../controllers/health.controller.js';

export const router: Router = Router();

router.get('/', showHome);
router.get('/health', showHealth);
