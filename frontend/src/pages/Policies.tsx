import React from 'react';
import { Settings, Shield } from 'lucide-react';
import Button from '@/components/ui/Button';

const Policies: React.FC = () => {
  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-3xl font-bold text-gray-900">Protection Policies</h1>
      </div>

      <div className="card">
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-lg font-semibold text-gray-900">Current Policy</h2>
          <Button variant="outline" size="sm">
            <Settings className="h-4 w-4 mr-2" />
            Edit Policy
          </Button>
        </div>

        <div className="text-center py-12 text-gray-500">
          <Shield className="h-12 w-12 mx-auto mb-4 text-gray-300" />
          <p>No protection policy configured</p>
          <p className="text-sm mt-2">Set up your crash protection preferences</p>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div className="card">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Crash Detection</h3>
          <div className="space-y-3">
            <div className="flex justify-between">
              <span className="text-gray-600">Threshold</span>
              <span className="font-medium">Not set</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-600">Multi-asset trigger</span>
              <span className="font-medium">Not set</span>
            </div>
          </div>
        </div>

        <div className="card">
          <h3 className="text-lg font-semibold text-gray-900 mb-4">Emergency Actions</h3>
          <div className="space-y-3">
            <div className="flex justify-between">
              <span className="text-gray-600">Max slippage</span>
              <span className="font-medium">Not set</span>
            </div>
            <div className="flex justify-between">
              <span className="text-gray-600">Preferred stablecoin</span>
              <span className="font-medium">Not set</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Policies;