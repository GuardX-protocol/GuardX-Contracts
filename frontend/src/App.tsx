import React from 'react';
import { BrowserRouter as Router, Routes, Route, Navigate } from 'react-router-dom';
import { WagmiConfig } from 'wagmi';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { wagmiConfig } from '@/config/wagmi';
import Layout from '@/components/layout/Layout';
import Dashboard from '@/pages/Dashboard';
import Deposit from '@/pages/Deposit';
import Policies from '@/pages/Policies';
import Audit from '@/pages/Audit';
import Onboarding from '@/pages/Onboarding';
import '@/styles/globals.css';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 1000 * 60 * 5, // 5 minutes
      cacheTime: 1000 * 60 * 10, // 10 minutes
    },
  },
});

const App: React.FC = () => {
  return (
    <QueryClientProvider client={queryClient}>
      <WagmiConfig config={wagmiConfig}>
        <Router>
          <Routes>
            <Route path="/" element={<Layout />}>
              <Route index element={<Navigate to="/dashboard" replace />} />
              <Route path="dashboard" element={<Dashboard />} />
              <Route path="deposit" element={<Deposit />} />
              <Route path="policies" element={<Policies />} />
              <Route path="audit" element={<Audit />} />
              <Route path="onboarding" element={<Onboarding />} />
            </Route>
          </Routes>
        </Router>
      </WagmiConfig>
    </QueryClientProvider>
  );
};

export default App;