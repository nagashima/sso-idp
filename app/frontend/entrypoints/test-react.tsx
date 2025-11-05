import '@vitejs/plugin-react-swc/preamble';
import React from 'react';
import { createRoot } from 'react-dom/client';

const TestReactComponent: React.FC = () => {
  return (
    <div className="p-4 bg-green-100 border border-green-300 rounded">
      <h3 className="text-lg font-semibold text-green-800 mb-2">
        ✅ React + Vite HMR動作確認！
      </h3>
      <div className="space-y-1 text-sm text-green-700">
        <p>• Vite + Rails 8.0統合: OK</p>
        <p>• React 19.2.0: OK</p>
        <p>• SWC Plugin: OK</p>
        <p>• TailwindCSS: OK</p>
        <p>• HMR WebSocket: https-portal経由で成功🎉</p>
      </div>
    </div>
  );
};

document.addEventListener('DOMContentLoaded', () => {
  const container = document.getElementById('test-react-component');
  if (container) {
    const root = createRoot(container);
    root.render(<TestReactComponent />);
  }
});
