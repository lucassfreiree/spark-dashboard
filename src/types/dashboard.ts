export type DeployStatus = 'success' | 'failed' | 'running' | 'idle'
export type AgentType = 'Claude' | 'Copilot' | 'idle'
export type PipelineStage = 'Setup' | 'Session Guard' | 'Apply & Push' | 'CI Gate' | 'Promote' | 'Save State' | 'Audit'

export interface DashboardState {
  controllerVersion: string
  agentVersion: string
  lastDeploy: {
    date: string
    component: string
    status: DeployStatus
  }
  pipelineStatus: DeployStatus
  lastTriggerRun: number
  activeAgent: AgentType
  deployHistory: DeployRecord[]
  agentActivity: AgentActivity
  workflows: WorkflowInfo[]
  pipeline: PipelineInfo
  lastUpdated: string
}

export interface DeployRecord {
  id: string
  date: string
  component: string
  version: string
  status: DeployStatus
  run: number
  duration: string
}

export interface AgentActivity {
  timeline: TimelineEvent[]
  recentSessions: AgentSession[]
  lessonsLearned: Lesson[]
}

export interface TimelineEvent {
  id: string
  timestamp: string
  agent: AgentType
  action: string
  duration?: string
}

export interface AgentSession {
  id: string
  agent: AgentType
  startTime: string
  endTime?: string
  status: DeployStatus
  deploysCount: number
}

export interface Lesson {
  id: string
  date: string
  title: string
  description: string
  agent: AgentType
}

export interface WorkflowInfo {
  id: string
  name: string
  status: DeployStatus
  lastRun: string
  duration: string
  branch: string
}

export interface PipelineInfo {
  currentStage?: PipelineStage
  stages: StageInfo[]
}

export interface StageInfo {
  name: PipelineStage
  status: DeployStatus
  startTime?: string
  endTime?: string
  duration?: string
}
