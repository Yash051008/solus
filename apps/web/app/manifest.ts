import type { MetadataRoute } from 'next';

/** Lets browsers install Solus as an app (own window, own icon). */
export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'Solus Distribution',
    short_name: 'Solus',
    start_url: '/',
    display: 'standalone',
    background_color: '#141413',
    theme_color: '#1f6f4a',
    icons: [{ src: '/icon.svg', sizes: 'any', type: 'image/svg+xml', purpose: 'any' }],
  };
}
