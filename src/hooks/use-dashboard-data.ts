import { useState, useEffect, useCallback } from 'react'
import { DashboardState } from '@/types/dashboard'

const REFRESH_INTERVAL = 30000

const EMPTY_STATE: DashboardState = {
  lastSync: '',
  syncSource: '',
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

export function useDashboardData() {
  const [data, setData] = useState<DashboardState>(EMPTY_STATE)
  const [isLoading, setIsLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchData = useCallback(async () => {
    try {
      setIsLoading(true)
      setError(null)

      // Try fetching state.json from the same origin (synced by spark-sync-state.yml)
      const response = await fetch('/state.json?t=' + Date.now())

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`)
      }

      const json = await response.json()
      
      const processedData: DashboardState = {
        ...EMPTY_STATE,
        ...json,
        lastUpdated: json.lastSync || new Date().toISOString(),
        controllerVersion: json.controller?.version || json.versionRules?.currentController || '?',
        agentVersion: json.agent?.version || json.versionRules?.currentAgent || '?',
        lastTriggerRun: json.versionRules?.lastTriggerRun || 0,
        pipelineStatus: json.pipeline?.status as any || 'idle',
        lastDeploy: json.deployHistory?.[0] || undefined,
        activeAgent: json.sessionLock?.agentId || 'none',
        workflows: json.recentWorkflows || [],
        agentActivity: {
          events: [],
          sessions: json.agents?.copilot?.sessions || [],
          timeline: [],
          recentSessions: json.agents?.copilot?.sessions || [],
          lessonsLearned: json.lessonsLearned?.copilotLessons || []
        }
      }
      
      if (processedData.pipeline) {
        processedData.pipeline.stages = json.pipelineStages || []
        processedData.pipeline.currentStage = json.pipeline?.component || undefined
      }
      
      setData(processedData)
    } catch (err) {
      console.warn('Failed to fetch state.json:', err)
      setError('Live data unavailable — showing last known state')
      setData(prev => ({ ...prev, lastUpdated: new Date().toISOString() }))
    } finally {
      setIsLoading(false)
    }
  }, [])

  useEffect(() => {
    fetchData()
    const interval = setInterval(fetchData, REFRESH_INTERVAL)
    return () => clearInterval(interval)
  }, [fetchData])

  return { data, isLoading, error, refetch: fetchData }
}
