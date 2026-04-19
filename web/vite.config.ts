/// <reference types="vitest/config" />
import fs from 'fs'
import { execSync } from 'child_process'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import path from 'path'

const repoRoot = path.resolve(__dirname, '..')
const releasePolicy = JSON.parse(
  fs.readFileSync(path.resolve(repoRoot, 'config/release-policy.json'), 'utf8'),
)

function safeGitSha(): string {
  try {
    return execSync('git rev-parse --short HEAD', {
      cwd: repoRoot,
      stdio: ['ignore', 'pipe', 'ignore'],
    }).toString().trim()
  } catch {
    return ''
  }
}

const gitSha = process.env.GIT_SHA || safeGitSha()
const buildTime = process.env.BUILD_TIME || new Date().toISOString()
const buildId = process.env.RELEASE_BUILD_ID || gitSha || 'web-local'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  define: {
    __APP_VERSION__: JSON.stringify(releasePolicy.version),
    __APP_RELEASE_PUBLISHED_AT__: JSON.stringify(releasePolicy.publishedAt),
    __APP_BUILD_ID__: JSON.stringify(buildId),
    __APP_BUILD_TIME__: JSON.stringify(buildTime),
    __APP_GIT_SHA__: JSON.stringify(gitSha),
  },
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    css: false,
    include: ['src/**/*.{test,spec}.{ts,tsx}'],
    exclude: ['node_modules', 'dist', '.idea', '.git', '.cache'],
  },
})
