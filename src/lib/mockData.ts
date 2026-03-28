import { DashboardState } from '@/types/dashboard'

export const mockDashboardData: DashboardState = {
  controllerVersion: '3.6.8',
  agentVersion: '2.2.9',
  lastDeploy: {
    date: '2024-01-15T14:32:00Z',
    component: 'api-gateway',
    status: 'success'
  },
  pipelineStatus: 'idle',
  lastTriggerRun: 66,
  activeAgent: 'Claude',
  lastUpdated: new Date().toISOString(),
  deployHistory: [
    {
      id: '1',
      date: '2024-01-15T14:32:00Z',
      component: 'api-gateway',
      version: '2.1.3',
      status: 'success',
      run: 66,
      duration: '4m 32s'
    },
    {
      id: '2',
      date: '2024-01-15T13:15:00Z',
      component: 'auth-service',
      version: '1.8.2',
      status: 'success',
      run: 65,
      duration: '3m 18s'
    },
    {
      id: '3',
      date: '2024-01-15T11:45:00Z',
      component: 'frontend',
      version: '5.2.1',
      status: 'failed',
      run: 64,
      duration: '2m 45s'
    },
    {
      id: '4',
      date: '2024-01-15T10:20:00Z',
      component: 'database-migrations',
      version: '1.0.9',
      status: 'success',
      run: 63,
      duration: '6m 12s'
    },
    {
      id: '5',
      date: '2024-01-15T09:05:00Z',
      component: 'worker-service',
      version: '3.4.0',
      status: 'success',
      run: 62,
      duration: '5m 03s'
    },
    {
      id: '6',
      date: '2024-01-14T16:30:00Z',
      component: 'api-gateway',
      version: '2.1.2',
      status: 'success',
      run: 61,
      duration: '4m 15s'
    },
    {
      id: '7',
      date: '2024-01-14T15:10:00Z',
      component: 'notification-service',
      version: '1.2.5',
      status: 'failed',
      run: 60,
      duration: '1m 58s'
    },
    {
      id: '8',
      date: '2024-01-14T14:00:00Z',
      component: 'frontend',
      version: '5.2.0',
      status: 'success',
      run: 59,
      duration: '3m 42s'
    }
  ],
  agentActivity: {
    timeline: [
      {
        id: '1',
        timestamp: '2024-01-15T14:30:00Z',
        agent: 'Claude',
        action: 'Started deployment session',
        duration: '15m'
      },
      {
        id: '2',
        timestamp: '2024-01-15T13:00:00Z',
        agent: 'Claude',
        action: 'Completed auth-service deployment',
        duration: '20m'
      },
      {
        id: '3',
        timestamp: '2024-01-15T11:30:00Z',
        agent: 'Copilot',
        action: 'Failed frontend deployment - rollback initiated',
        duration: '10m'
      },
      {
        id: '4',
        timestamp: '2024-01-15T10:00:00Z',
        agent: 'Claude',
        action: 'Database migration completed',
        duration: '25m'
      },
      {
        id: '5',
        timestamp: '2024-01-15T09:00:00Z',
        agent: 'Copilot',
        action: 'Worker service deployed successfully',
        duration: '18m'
      }
    ],
    recentSessions: [
      {
        id: '1',
        agent: 'Claude',
        startTime: '2024-01-15T14:00:00Z',
        endTime: '2024-01-15T14:45:00Z',
        status: 'success',
        deploysCount: 2
      },
      {
        id: '2',
        agent: 'Copilot',
        startTime: '2024-01-15T11:00:00Z',
        endTime: '2024-01-15T11:30:00Z',
        status: 'failed',
        deploysCount: 1
      },
      {
        id: '3',
        agent: 'Claude',
        startTime: '2024-01-15T09:00:00Z',
        endTime: '2024-01-15T10:30:00Z',
        status: 'success',
        deploysCount: 2
      },
      {
        id: '4',
        agent: 'Copilot',
        startTime: '2024-01-14T16:00:00Z',
        endTime: '2024-01-14T16:45:00Z',
        status: 'success',
        deploysCount: 1
      }
    ],
    lessonsLearned: [
      {
        id: '1',
        date: '2024-01-15',
        title: 'Frontend Build Optimization',
        description: 'Reduced build time by caching node_modules. Apply cache strategy to all Node.js builds.',
        agent: 'Claude'
      },
      {
        id: '2',
        date: '2024-01-14',
        title: 'Database Migration Timing',
        description: 'Run migrations during low-traffic hours. Schedule for 2-4 AM UTC to minimize impact.',
        agent: 'Copilot'
      },
      {
        id: '3',
        date: '2024-01-13',
        title: 'Rollback Strategy',
        description: 'Implement automated rollback on CI Gate failure. Reduces manual intervention time by 80%.',
        agent: 'Claude'
      }
    ]
  },
  workflows: [
    {
      id: '1',
      name: 'Deploy Production',
      status: 'success',
      lastRun: '2024-01-15T14:32:00Z',
      duration: '4m 32s',
      branch: 'main'
    },
    {
      id: '2',
      name: 'Run Tests',
      status: 'success',
      lastRun: '2024-01-15T14:28:00Z',
      duration: '2m 15s',
      branch: 'main'
    },
    {
      id: '3',
      name: 'Security Scan',
      status: 'success',
      lastRun: '2024-01-15T14:25:00Z',
      duration: '1m 45s',
      branch: 'main'
    },
    {
      id: '4',
      name: 'Code Quality Check',
      status: 'success',
      lastRun: '2024-01-15T14:20:00Z',
      duration: '1m 20s',
      branch: 'main'
    },
    {
      id: '5',
      name: 'Build Docker Images',
      status: 'idle',
      lastRun: '2024-01-15T10:00:00Z',
      duration: '5m 12s',
      branch: 'develop'
    }
  ],
  pipeline: {
    currentStage: 'Audit',
    stages: [
      {
        name: 'Setup',
        status: 'success',
        startTime: '2024-01-15T14:28:00Z',
        endTime: '2024-01-15T14:28:30Z',
        duration: '30s'
      },
      {
        name: 'Session Guard',
        status: 'success',
        startTime: '2024-01-15T14:28:30Z',
        endTime: '2024-01-15T14:29:00Z',
        duration: '30s'
      },
      {
        name: 'Apply & Push',
        status: 'success',
        startTime: '2024-01-15T14:29:00Z',
        endTime: '2024-01-15T14:30:15Z',
        duration: '1m 15s'
      },
      {
        name: 'CI Gate',
        status: 'success',
        startTime: '2024-01-15T14:30:15Z',
        endTime: '2024-01-15T14:31:00Z',
        duration: '45s'
      },
      {
        name: 'Promote',
        status: 'success',
        startTime: '2024-01-15T14:31:00Z',
        endTime: '2024-01-15T14:31:30Z',
        duration: '30s'
      },
      {
        name: 'Save State',
        status: 'success',
        startTime: '2024-01-15T14:31:30Z',
        endTime: '2024-01-15T14:31:45Z',
        duration: '15s'
      },
      {
        name: 'Audit',
        status: 'success',
        startTime: '2024-01-15T14:31:45Z',
        endTime: '2024-01-15T14:32:00Z',
        duration: '15s'
      }
    ]
  }
}
