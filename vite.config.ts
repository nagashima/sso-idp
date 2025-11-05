import { defineConfig } from 'vite'
import RubyPlugin from 'vite-plugin-ruby'
import ReactSWC from '@vitejs/plugin-react-swc'

export default defineConfig({
  plugins: [
    RubyPlugin(),
    ReactSWC(),
  ],
  server: {
    // 環境変数が設定されている場合のみHMR設定を上書き（nginx経由用）
    // 設定されていない場合はViteのデフォルト動作（localhost:3000用）
    hmr: process.env.VITE_HMR_PROTOCOL ? {
      protocol: process.env.VITE_HMR_PROTOCOL as 'ws' | 'wss',
      host: process.env.VITE_HMR_HOST,
      clientPort: parseInt(process.env.VITE_HMR_PORT || '443')
    } : true
  }
})
