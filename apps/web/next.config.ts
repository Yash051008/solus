import type { NextConfig } from 'next';

const config: NextConfig = {
  // Workspace packages ship TypeScript source.
  transpilePackages: ['@solus/core', '@solus/db', '@solus/integrations'],
  poweredByHeader: false,
  // e-POD photos go through a server action; the epod bucket caps files at 5 MB.
  experimental: { serverActions: { bodySizeLimit: '6mb' } },
};

export default config;
