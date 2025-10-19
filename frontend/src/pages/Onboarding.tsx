import React from 'react';
import { CheckCircle, Circle, ArrowRight } from 'lucide-react';
import Button from '@/components/ui/Button';

const Onboarding: React.FC = () => {
  const steps = [
    { id: 1, title: 'Connect Wallet', completed: false, current: true },
    { id: 2, title: 'Setup Vincent Wallet', completed: false, current: false },
    { id: 3, title: 'Configure Delegation', completed: false, current: false },
    { id: 4, title: 'Verify Setup', completed: false, current: false },
    { id: 5, title: 'Complete Onboarding', completed: false, current: false },
  ];

  return (
    <div className="space-y-6">
      <div className="text-center">
        <h1 className="text-3xl font-bold text-gray-900 mb-2">Welcome to GuardX</h1>
        <p className="text-lg text-gray-600">Let's set up your automated crash protection</p>
      </div>

      {/* Progress Steps */}
      <div className="card">
        <div className="space-y-4">
          {steps.map((step, index) => (
            <div key={step.id} className="flex items-center">
              <div className="flex-shrink-0">
                {step.completed ? (
                  <CheckCircle className="h-6 w-6 text-success-600" />
                ) : step.current ? (
                  <div className="h-6 w-6 rounded-full bg-primary-600 flex items-center justify-center">
                    <span className="text-white text-sm font-medium">{step.id}</span>
                  </div>
                ) : (
                  <Circle className="h-6 w-6 text-gray-300" />
                )}
              </div>
              <div className="ml-4 flex-1">
                <h3 className={`text-sm font-medium ${
                  step.current ? 'text-primary-600' : step.completed ? 'text-success-600' : 'text-gray-500'
                }`}>
                  {step.title}
                </h3>
              </div>
              {index < steps.length - 1 && (
                <ArrowRight className="h-4 w-4 text-gray-300 ml-4" />
              )}
            </div>
          ))}
        </div>
      </div>

      {/* Current Step Content */}
      <div className="card">
        <h2 className="text-xl font-semibold text-gray-900 mb-4">Step 1: Connect Your Wallet</h2>
        <p className="text-gray-600 mb-6">
          To get started with GuardX, you'll need to connect your Ethereum wallet. 
          This allows us to monitor your assets and execute protection strategies on your behalf.
        </p>
        
        <div className="space-y-4">
          <div className="p-4 bg-blue-50 rounded-lg border border-blue-200">
            <h3 className="font-medium text-blue-900 mb-2">What happens next?</h3>
            <ul className="text-sm text-blue-800 space-y-1">
              <li>• We'll help you set up a Vincent wallet for secure delegation</li>
              <li>• Configure automated protection policies</li>
              <li>• Test the setup with a small transaction</li>
              <li>• Start protecting your assets automatically</li>
            </ul>
          </div>

          <Button className="w-full">
            Connect Wallet to Continue
          </Button>
        </div>
      </div>
    </div>
  );
};

export default Onboarding;