import React from 'react';
import { Plus, Wallet } from 'lucide-react';
import Button from '@/components/ui/Button';

const Deposit: React.FC = () => {
  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-3xl font-bold text-gray-900">Deposit Assets</h1>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <div className="card">
          <h2 className="text-lg font-semibold text-gray-900 mb-4">Available Tokens</h2>
          <div className="text-center py-12 text-gray-500">
            <Wallet className="h-12 w-12 mx-auto mb-4 text-gray-300" />
            <p>Connect your wallet to view available tokens</p>
          </div>
        </div>

        <div className="card">
          <h2 className="text-lg font-semibold text-gray-900 mb-4">Deposit Form</h2>
          <div className="space-y-4">
            <div>
              <label className="label">Select Token</label>
              <select className="input" disabled>
                <option>Connect wallet first</option>
              </select>
            </div>
            
            <div>
              <label className="label">Amount</label>
              <input
                type="number"
                className="input"
                placeholder="0.0"
                disabled
              />
            </div>

            <Button className="w-full" disabled>
              <Plus className="h-4 w-4 mr-2" />
              Deposit Asset
            </Button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Deposit;