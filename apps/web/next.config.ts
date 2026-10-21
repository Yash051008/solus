import type { NextConfig } from 'next';

const config: NextConfig = {
  // Workspace packages ship TypeScript source.
  transpilePackages: ['@solus/core', '@solus/db', '@solus/integrations'],
  poweredByHeader: false,
};

export default config;
