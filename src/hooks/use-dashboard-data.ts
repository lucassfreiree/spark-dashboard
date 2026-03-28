import { useState, useEffect, useCallback } from 'react'
import { DashboardState, DeployStatus, AgentType } from '@/types/dashboard'
import { mockDashboardData } from '@/lib/mockData'

const REFRESH_INTERVAL = 30000

interface RemoteState {
  lastSync?: string
  controller?: { version?: string; status?: string; ciResult?: string; promoted?: boolean; lastSha?: string }
  agent?: { version?: string; status?: string; ciResult?: string; promoted?: boolean }
  pipeline?: { status?: string; lastRun?: number; component?: string; version?: string }
  activeAgent?: { name?: string; status?: string; task?: string | null }
  copilotMemory?: { sessionCount?: number; lastSession?: string; lessonsCount?: number }
}

function mapStatus(status: string | undefined): DeployStatus {
  if (status === 'success' || status === 'failed' || status === 'running' || status === 'idle') {
    return status
  }
  if (status === 'ci-failed' || status === 'failure') return 'failed'
  if (status === 'pending' || status === 'timeout') return 'running'
  return 'idle'
}

function mapAgent(name: string | undefined): AgentType {
  if (name === 'Claude' || name === 'Copilot') return name
  return 'idle'
}

function mergeState(remote: RemoteState, prev: DashboardState): DashboardState {
  return {
    ...prev,
    controllerVersion: remote.controller?.version ?? prev.controllerVersion,
    agentVersion: remote.agent?.version ?? prev.agentVersion,
    pipelineStatus: remote.pipeline ? mapStatus(remote.pipeline.status) : prev.pipelineStatus,
    lastTriggerRun: remote.pipeline?.lastRun ?? prev.lastTriggerRun,
    activeAgent: remote.activeAgent ? mapAgent(remote.activeAgent.name) : prev.activeAgent,
    lastDeploy: remote.pipeline
      ? {
          date: remote.lastSync ?? prev.lastDeploy.date,
          component: remote.pipeline.component ?? prev.lastDeploy.component,
          status: mapStatus(remote.pipeline.status),
        }
      : prev.lastDeploy,
    lastUpdated: new Date().toISOString(),
  }
}

export function useDashboardData() {
  const [data, setData] = useState<DashboardState>(mockDashboardData)
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const fetchData = useCallback(async () => {
    try {
      setIsLoading(true)
      setError(null)

      const response = await fetch('/state.json')

      if (!response.ok) {
        throw new Error('Failed to fetch data')
      }

      const jsonData = await response.json()
      setData(prev => mergeState(jsonData, prev))
    } catch (err) {
      console.error('Error fetching dashboard data:', err)
      setError('Using cached data - live updates unavailable')
      setData(prev => ({
        ...prev,
        lastUpdated: new Date().toISOString()
      }))
    } finally {
      setIsLoading(false)
    }
  }, [])

  useEffect(() => {
    fetchData()

    const interval = setInterval(() => {
      fetchData()
    }, REFRESH_INTERVAL)

    return () => clearInterval(interval)
  }, [fetchData])

  return { data, isLoading, error, refetch: fetchData }
}
