export default defineNuxtConfig({
  modules: ['@nuxt/ui', 'nuxt-charts'],

  // Dashboard privé et rafraîchi en continu : rendu côté client uniquement
  ssr: false,

  css: ['~/assets/css/main.css'],

  // Pas de téléchargement de polices : l'appli doit fonctionner sans accès externe
  ui: {
    fonts: false,
  },

  // Icônes servies depuis @iconify-json/lucide, sans appel à l'API Iconify
  icon: {
    serverBundle: {
      collections: ['lucide'],
    },
  },

  // Surchargeables par variables d'environnement NUXT_* (voir docker-compose)
  runtimeConfig: {
    dockerHost: 'http://docker-socket-proxy:2375',
    dockerActionsHost: 'http://docker-socket-proxy-actions:2375',
    prometheusUrl: 'http://prometheus:9090',
    wudUrl: 'http://wud:3000',
    wudUser: 'admin',
    wudPassword: '',
    backupStatusDir: '/status/restic',
    backupRequestDir: '/requests/restic',
    trivyStatusDir: '/status/trivy',
    trivyRequestDir: '/requests/trivy',
    public: {
      wudPublicUrl: '',
      defaultProject: 'docker-master',
    },
  },

  devtools: { enabled: false },
  compatibilityDate: '2026-09-01',
})
