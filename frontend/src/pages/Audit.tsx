import React from 'react';
import { Download, Search, FileText } from 'lucide-react';
import Button from '@/components/ui/Button';

const Audit: React.FC = () => {
  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-3xl font-bold text-gray-900">Audit Trail</h1>
        <Button variant="outline" size="sm">
          <Download className="h-4 w-4 mr-2" />
          Export Data
        </Button>
      </div>

      <div className="card">
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-lg font-semibold text-gray-900">Transaction History</h2>
          <div className="flex items-center space-x-2">
            <div className="relative">
              <Search className="h-4 w-4 absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400" />
              <input
                type="text"
                placeholder="Search transactions..."
                className="pl-10 pr-4 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-primary-500 focus:border-primary-500"
              />
            </div>
          </div>
        </div>

        <div className="text-center py-12 text-gray-500">
          <FileText className="h-12 w-12 mx-auto mb-4 text-gray-300" />
          <p>No transactions found</p>
          <p className="text-sm mt-2">Your transaction history will appear here</p>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div className="card text-center">
          <h3 className="text-lg font-semibold text-gray-900 mb-2">Total Transactions</h3>
          <p className="text-3xl font-bold text-primary-600">0</p>
        </div>

        <div className="card text-center">
          <h3 className="text-lg font-semibold text-gray-900 mb-2">Emergency Actions</h3>
          <p className="text-3xl font-bold text-warning-600">0</p>
        </div>

        <div className="card text-center">
          <h3 className="text-lg font-semibold text-gray-900 mb-2">Total Volume</h3>
          <p className="text-3xl font-bold text-success-600">$0.00</p>
        </div>
      </div>
    </div>
  );
};

export default Audit;