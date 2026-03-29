// Mock data removed — dashboard now reads real state.json from spark-sync-state.yml
// This file kept as empty export for backward compatibility
import { DashboardState } from '@/types/dashboard'

export const mockDashboardData: DashboardState = {
  lastSync: '',
  syncSource: 'mock',
  controller: { version: '?', status: 'unknown', ciResult: 'unknown', promoted: false, lastSha: '?', updatedAt: null },
  agent: { version: '?', status: 'unknown', ciResult: 'unknown', promoted: false, lastSha: '?', updatedAt: null },
  pipeline: { status: 'idle', lastRun: 0, component: '?', version: '?', promote: false, workspace: '?' },
  agents: {
    claude: { status: 'idle', task: null, phase: null, lastUpdated: null, lastAction: null },
    copilot: { sessionCount: 0, lastSession: 'none', lessonsCount: 0, lastUpdated: null },
    codex: { sessionCount: 0, lastSession: 'none', lessonsCount: 0, lastUpdated: null }
  },
  sessionLock: { agentId: 'none', expiresAt: null, acquiredAt: null, operation: null },
  health: {},
  ciMonitor: {},
  workspaces: [],
  recentWorkflows: [],
  openPRs: [],
  deployHistory: [],
  lessonsLearned: { total: 0, copilot: 0, codex: 0 },
  versionRules: { currentController: '?', currentAgent: '?', pattern: '', lastTriggerRun: 0, lastSuccessfulRun: 0 },
  executionHistory: [],
  knownErrors: [],
  pipelineStages: [],
  corporateReal: {
    controller: { sourceVersion: '?', capTag: '?', drift: false, driftDetail: null },
    agent: { sourceVersion: '?', capTag: '?', drift: false, driftDetail: null },
    lastChecked: ''
  },
  metadata: { autopilotRepo: 'lucassfreiree/autopilot', sparkRepo: 'lucassfreiree/spark-dashboard', totalAgents: 3, totalWorkspaces: 4, syncInterval: '5 minutes', stateVersion: 3 },
  lastUpdated: new Date().toISOString()
}
