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

      // Try with base path first (GitHub Pages), then root
      let response = await fetch(import.meta.env.BASE_URL + 'state.json?t=' + Date.now())
      if (!response.ok) {
        response = await fetch('/state.json?t=' + Date.now())
      }
      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const json = await response.json()
      setData({
        ...EMPTY_STATE,
        ...json,
        lastUpdated: json.lastSync || new Date().toISOString()
      })
    } catch (err) {
      console.warn('Failed to fetch state.json:', err)
      setError('Live data unavailable')
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
