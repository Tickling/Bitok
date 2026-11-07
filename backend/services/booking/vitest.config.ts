import { resolve } from 'node:path';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  resolve: { alias: { '@bitok/shared-kernel': resolve(__dirname, '../../shared-kernel/src/index.ts') } },
  test: { include: ['test/**/*.spec.ts'] },
});
