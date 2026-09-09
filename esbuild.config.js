import { build } from 'esbuild';

/**
 * Compile src/front/*.ts vers public/js/*.js.
 *
 * esbuild ne vérifie PAS les types, il ne fait que transformer.
 * La vérification passe par `npm run typecheck` et par la CI.
 */
await build({
  entryPoints: ['src/front/main.ts'],
  outdir: 'public/js',
  bundle: true,
  format: 'esm',
  target: 'es2022',
  minify: process.env.NODE_ENV === 'production',
  sourcemap: process.env.NODE_ENV !== 'production',
  logLevel: 'info',
});
